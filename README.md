# Model-Moose-Importer

Loads a [Model](../README.md) into a Moose/Famix model **without going through JSON**.
The Rust side exposes the frozen `Model` as flat arrays (crate
[`model-ffi`](../crates/model-ffi), a C ABI); the Pharo side reads them through
UFFI and creates the Famix objects directly.

```
model.json ──► model-ffi (Rust, cdylib) ──UFFI──► ModelImporter ──► FamixJavaModel
               columns, no Famix knowledge         FM3 metamodel of the image
```

Today it targets **FamixJava**. FamixTypeScript and FamixPython are planned (see
[Other languages](#other-languages)).

## Why

The usual path is `Model` → Moose JSON (`model-moose`) → `importFromJSONStream:`,
which parses text, rebuilds every string and resolves dangling references through
one `FMFutureEntity` per entity. Here Pharo reads integer columns and strings that
point into the model's own memory, then only pays for creating the Famix objects.

Measured on `java/util` of the JDK (370 files, 65 381 entities, 122 140 occurrence
sites), same image, 3 runs each, after a garbage collection:

| Path | Time | Famix objects |
|---|---|---|
| Moose JSON (`importFromJSONStream:`) | 8.7 s | 354 163 |
| This importer (includes Rust reading `model.json`, reading sources, anchors) | 2.3 s | 350 602 |

The JSON figure leaves out the Moose export itself (0.9 s of Rust) and re-reading
the model to export it. The object counts differ slightly, see
[Parity with the JSON import](#parity-with-the-json-import).

Where the time goes (first measurement, 65 k entities, ms): open the model 146,
read columns 171, create entities 182, containers 99, associations 768, anchors
540, add to the model 102. Creating Famix objects dominates, as expected.

## Requirements

- A Pharo image with Moose: `MooseModel` (`Moose-Core`), the target Famix entities
  (`Famix-Java-Entities`) and UFFI. Developed on Pharo 13.1.
- The native library `libmodel_ffi` built from this repository (Rust toolchain
  pinned in `rust-toolchain.toml`).
- A `model.json` produced by Model, and the source files it was built from (for
  source anchors).

Developed and tested on macOS (arm64). Linux and Windows are expected to work (the
library name is the only platform-specific part) but are untested.

## Install

### 1. Build the native library

```bash
cargo build --release -p model-ffi
```

This produces `target/release/libmodel_ffi.dylib` (`.so` on Linux, `.dll` on
Windows).

### 2. Load the Pharo package

```smalltalk
Metacello new
	baseline: 'ModelMooseImporter';
	repository: 'github://badetitou/Model:main/pharo/src';
	load.
```

Replace `main` with the branch you want. The baseline loads the `Minimal` and
`ModelJava` groups of
[`github://moosetechnology/Famix:development/src`](https://github.com/moosetechnology/Famix)
and the package `Model-Moose-Importer`.

> The baseline has been parsed with Pharo's Tonel reader but a full load from
> GitHub has not been tested yet.

### 3. Tell Pharo where the library is

```smalltalk
ModelLibrary libraryPath: '/path/to/Model/target/release/libmodel_ffi.dylib'.
ModelLibrary uniqueInstance abiVersion.   "→ 1"
```

## Produce a model

```bash
cargo run --release -p model-factory --example build -- /path/to/sources \
    --no-scip --no-cache --json model.json
```

`--no-scip` builds from tree-sitter only; drop it to use existing SCIP indexes
(relations are then compiler-grade). See `docs/usage.md` for the other options.

## Use

```smalltalk
| model report |
model := FamixJavaModel new.
report := ModelImporter new
	prefix: 'FamixJava';
	importModelAt: '/path/to/model.json'
	into: model
	sourceRoot: '/path/to/sources'.
report
```

- `prefix:` is the class-name prefix of the target Famix metamodel.
- `sourceRoot:` is the directory the model's file paths are relative to (the root
  you gave to the build). It is needed to compute the character offsets of the
  source anchors. If a file cannot be read, its anchors are skipped and counted
  under `anchor:unreadable-file`.
- The result is an array of associations: `#entities` (entities created),
  `#associations` (associations **and** anchors created), `#skippedRelations`
  (a dictionary of what was not imported, by relation kind).

## What is imported

### Entities

A Model kind name is mapped to a simple FM3 class name by
`ModelImporter>>kindClassNames` (data, not logic), then to
`<prefix><name>`:

| Model kind | FM3 class |
|---|---|
| `namespace` | `Package` |
| `class`, `record` | `Class` |
| `interface` | `Interface` |
| `annotation_type` | `AnnotationType` |
| `enum` | `Enum` |
| `method`, `constructor` | `Method` |
| `field`, `constant` | `Attribute` |
| `enum_constant` | `EnumValue` |
| `parameter` | `Parameter` |
| `local_variable` | `LocalVariable` |
| `type_parameter` | `TypeParameter` |
| `annotation` | `AnnotationInstance` |
| `comment` | `Comment` |

Other kinds (for example `file`) get no entity. External entities are flagged
`isStub`.

`KindInfo.fm3` is empty for models built from sources, which is why the mapping
lives here.

### Containers

The container property (`parentType`, `parentPackage`, `parentBehaviouralEntity`,
`commentedEntity`...) is found through the FM3 metamodel of the image
(`FM3Class>>allProperties`, `isContainer`, property type), and set through its
setter so the opposite side is maintained. One preference is explicit, because the
FM3 types alone are ambiguous: types go in `typeContainer`, as the Moose exporter
writes them (`ModelImporter>>preferredContainers`).

### Associations

One association per occurrence site, with a source anchor:

| Model relation | Famix |
|---|---|
| `calls` | `Invocation` (sender, candidate) |
| `accesses` | `Access` (`isWrite` from the site's write flag) |
| `declared_type` | `EntityTyping` (no anchor) |
| `references` | `Reference` |
| `imports` | `Import` |
| `inherits`, `implements` | `Inheritance`, or `Implementation` for a class that targets an interface |

Rules borrowed from the Moose exporter so that Famix accepts the result:

- **Source of a call, access or reference**: the entity itself if it is callable,
  otherwise its nearest callable ancestor (a field initialiser in an anonymous
  class belongs to the enclosing method).
- **Source of an import** when it is a file: the first top-level type of that file.
- **Target of a typing or a reference**: must be a type (`Class`, `Interface`,
  `Enum`, `AnnotationType`, `TypeParameter`). The FM3 traits of some types
  (interfaces) do not say so, so this one is not read from the metamodel.
- **Everything else**: both ends are checked against the FM3 type of the property;
  an association Famix would reject is skipped and counted.

### Anchors

`FamixJavaIndexedFileAnchor` with an absolute `fileName` and 1-based, inclusive
character offsets (a character is a Unicode scalar value, as Pharo counts).
Offsets are computed by the library (`model_char_offsets`) from the model's
line/byte-column ranges, all ranges of a file in one call.

## Parity with the JSON import

On a small Java project the result is **identical** to the JSON import: same 22
objects, names, containers, association properties, anchor positions and paths.

On `java/util`, counts of `Access`, `EntityTyping`, `Invocation` and `Reference`
match the JSON import. The remaining differences all come from things this
importer does not do, or from filters of the exporter:

| Difference | Cause |
|---|---|
| 77 more `Import` | The exporter does not attach imports to a file whose first top-level type is a generic interface or an exception; this importer does. |
| 854 more `Comment` | Comments whose parent is a file (license headers); the exporter drops them. |
| 931 more anchors | Exactly the two rows above. |
| `ParametricClass`, `ParametricInterface`, `ParametricMethod`, `Exception` | Same entities, but the exporter writes a more specific class. Here they are `Class`, `Interface`, `Method`. |
| 5 402 `ImplicitVariable` (`self`) and 21 stub `AnnotationType` | Created only by the exporter. |

## Not done yet

- Primitive properties (`visibility`, `isAbstract`, `isFinal`, modifiers...).
- `Parametric*`, `Exception`, `ImplicitVariable`, stub annotation types.
- `throws`, and dotted package names split into nested packages.
- The `model.json` still goes through Rust's JSON reader (146 ms on `java/util`);
  a binary format read without parsing is possible later.
- Not measured on very large models (the 1.4 GB sample was not tried; millions of
  associations may exhaust an image).

## Other languages

`prefix:` selects the target metamodel and the container and association checks
read its FM3 description, so the code is not Java-specific. The Model-kind →
FM3-class table is: `kindClassNames` returns the Java one. For FamixTypeScript or
FamixPython, override `kindClassNames` (and `preferredContainers` if needed) in a
subclass, load the corresponding Famix metamodel in the image, and compare with
the JSON import. None of this has been tried yet.

## Architecture

| Piece | Role |
|---|---|
| `crates/model-ffi` | C ABI over a frozen `Model`; depends on `model-core` only (and `serde_json` to open a `model.json`). Flat columns, string references, entity props as JSON, `model_char_offsets`. `unsafe` is confined to this crate. |
| `ModelLibrary` | UFFI binding (`FFILibrary`) and column readers: `uint32Column:count:`, `uint8Column:count:`, `stringColumn:count:`, `charOffsetsIn:ranges:`. |
| `ModelImporter` | Reads all columns, then creates entities, links containers, creates associations, resolves anchors, adds everything with one `silentlyAddAll:`. |
| `BaselineOfModelMooseImporter` | Metacello baseline. |

The C ABI is versioned (`model_abi_version`, currently 1). Columns are
little-endian arrays; an absent `u32` is `u32::MAX` (mapped to `nil` by
`uint32Column:count:`); a string is `{ pointer, u32 length }` pointing into the
model, with a null pointer for an absent string. The Pharo side copies every column
before calling `model_free`, so nothing native is kept alive.

## Pitfalls

- **Never read a column with `FFIExternalArray fromPointer:type:size:`.** It
  crashed the image. Columns are copied with `LibC memCopy:to:size:` instead
  (`ModelLibrary>>uint32Column:count:`).
- A crash of the image loses any class not saved: keep the Tonel sources in
  `pharo/src` as the source of truth.
- `ModelLibrary libraryPath:` must be set before the first call: the library name
  is read from it (`macLibraryName`, `unix64LibraryName`, `win32LibraryName`).
- `ModelImporter>>importModelAt:into:sourceRoot:` signals an error with the
  library's message (`model_last_error`) if the model cannot be opened.

## Development

- Tonel sources are in `pharo/src`; edit them in the image (the MCP Pharo tools
  work) and export, or edit the files and reload.
- Check parity after any change: import the same model with this importer and with
  `Model → Moose JSON → importFromJSONStream:` (`cargo run -p model-moose
  --release --example export -- <model.json> <out.json> --root <sources>`), then
  compare counts per class, names, containers and anchors.
- Rust side: `cargo fmt --check`, `cargo clippy --workspace --all-targets -- -D
  warnings`, `cargo test --workspace`.
