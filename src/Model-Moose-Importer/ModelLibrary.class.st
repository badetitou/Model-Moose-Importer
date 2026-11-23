"
UFFI binding to model-ffi (C ABI over a frozen Model). Set ModelLibrary libraryPath: to the absolute path of libmodel_ffi.dylib / .so / .dll before use. hasBuild = 1 when the library was compiled with the build feature, which enables build:scip:reindex:languages:scope: (model from sources, no JSON).
"
Class {
	#name : 'ModelLibrary',
	#superclass : 'FFILibrary',
	#classInstVars : [
		'libraryPath'
	],
	#category : 'Model-Moose-Importer',
	#package : 'Model-Moose-Importer'
}

{ #category : 'accessing' }
ModelLibrary class >> libraryPath [

	^ libraryPath
]

{ #category : 'accessing' }
ModelLibrary class >> libraryPath: aStringOrFileReference [

	libraryPath := aStringOrFileReference asFileReference pathString
]

{ #category : 'ffi' }
ModelLibrary >> abiVersion [
	^ self ffiCall: #(uint32 model_abi_version ())
]

{ #category : 'ffi' }
ModelLibrary >> build: aRoot scip: aScip reindex: aReindex languages: aLanguages scope: aScope [
	"Builds the model of the sources under aRoot in-process (no JSON). Answers a handle, null on error. aScip: 0 tree-sitter only; aReindex: 0 never, 1 if missing, 2 if stale, 3 always; aLanguages and aScope: comma-separated, empty for all."
	^ self ffiCall: #(void * model_build (String aRoot, uint32 aScip, uint32 aReindex, String aLanguages, String aScope))
]

{ #category : 'reading' }
ModelLibrary >> buildReportOf: aHandle [
	"Counts and warnings of a build, '' for a model opened from a file."

	| lengthBytes pointer bytes length |
	lengthBytes := ByteArray new: 4.
	pointer := self primBuildReport: aHandle len: lengthBytes.
	length := lengthBytes unsignedLongAt: 1.
	length = 0 ifTrue: [ ^ '' ].
	bytes := ByteArray new: length.
	LibC memCopy: pointer to: bytes size: length.
	^ bytes utf8Decoded
]

{ #category : 'reading' }
ModelLibrary >> charOffsetsIn: aPath ranges: aCollectionOfQuadruples [
	"Answers (start, end) character offsets (1-based, inclusive) per range, or nil if the file cannot be read."

	| count rangeBytes out rc |
	count := aCollectionOfQuadruples size.
	count = 0 ifTrue: [ ^ #(  ) ].
	rangeBytes := ByteArray new: count * 16.
	aCollectionOfQuadruples doWithIndex: [ :q :i |
			1 to: 4 do: [ :k |
				rangeBytes
					unsignedLongAt: i - 1 * 16 + (k - 1 * 4) + 1
					put: (q at: k) ] ].
	out := ByteArray new: count * 8.
	rc := self
		      charOffsetsPath: aPath
		      ranges: rangeBytes
		      count: count
		      into: out.
	rc = 0 ifFalse: [ ^ nil ].
	^ (1 to: count) collect: [ :i |
			  {
				  (out unsignedLongAt: i - 1 * 8 + 1).
				  (out unsignedLongAt: i - 1 * 8 + 5) } ]
]

{ #category : 'ffi' }
ModelLibrary >> charOffsetsPath: aPath ranges: aRangesBytes count: n into: anOutBytes [
	^ self ffiCall: #(int model_char_offsets (String aPath, void * aRangesBytes, uint32 n, void * anOutBytes))
]

{ #category : 'ffi' }
ModelLibrary >> entityCount: aHandle [
	^ self ffiCall: #(uint64 model_entity_count (void * aHandle))
]

{ #category : 'ffi' }
ModelLibrary >> entityFiles: aHandle [
	^ self ffiCall: #(void * model_entity_files (void * aHandle))
]

{ #category : 'ffi' }
ModelLibrary >> entityFlags: aHandle [
	^ self ffiCall: #(void * model_entity_flags (void * aHandle))
]

{ #category : 'reading' }
ModelLibrary >> entityKeys: aHandle [
	^ self ffiCall: #(void * model_entity_keys (void * aHandle))
]

{ #category : 'ffi' }
ModelLibrary >> entityKinds: aHandle [
	^ self ffiCall: #(void * model_entity_kinds (void * aHandle))
]

{ #category : 'ffi' }
ModelLibrary >> entityNames: aHandle [
	^ self ffiCall: #(void * model_entity_names (void * aHandle))
]

{ #category : 'ffi' }
ModelLibrary >> entityParents: aHandle [
	^ self ffiCall: #(void * model_entity_parents (void * aHandle))
]

{ #category : 'ffi' }
ModelLibrary >> entityRanges: aHandle [
	^ self ffiCall: #(void * model_entity_ranges (void * aHandle))
]

{ #category : 'ffi' }
ModelLibrary >> free: aHandle [
	^ self ffiCall: #(void model_free (void * aHandle))
]

{ #category : 'ffi' }
ModelLibrary >> hasBuild [
	"1 when the library was compiled with the build feature (model_build exists)."
	^ self ffiCall: #(uint32 model_has_build ())
]

{ #category : 'ffi' }
ModelLibrary >> kindArchetypes: aHandle [
	^ self ffiCall: #(void * model_kind_archetypes (void * aHandle))
]

{ #category : 'ffi' }
ModelLibrary >> kindCount: aHandle [
	^ self ffiCall: #(uint64 model_kind_count (void * aHandle))
]

{ #category : 'ffi' }
ModelLibrary >> kindFm3: aHandle [
	^ self ffiCall: #(void * model_kind_fm3 (void * aHandle))
]

{ #category : 'ffi' }
ModelLibrary >> kindNames: aHandle [
	^ self ffiCall: #(void * model_kind_names (void * aHandle))
]

{ #category : 'ffi' }
ModelLibrary >> lastError [
	^ self ffiCall: #(String model_last_error ())
]

{ #category : 'accessing platform' }
ModelLibrary >> macLibraryName [

	^ self class libraryPath
]

{ #category : 'ffi' }
ModelLibrary >> open: aPath [
	^ self ffiCall: #(void * model_open (String aPath))
]

{ #category : 'ffi' }
ModelLibrary >> primBuildReport: aHandle len: aBuffer [
	^ self ffiCall: #(void * model_build_report (void * aHandle, void * aBuffer))
]

{ #category : 'ffi' }
ModelLibrary >> relationCount: aHandle [
	^ self ffiCall: #(uint64 model_relation_count (void * aHandle))
]

{ #category : 'ffi' }
ModelLibrary >> relationFrom: aHandle [
	^ self ffiCall: #(void * model_relation_from (void * aHandle))
]

{ #category : 'ffi' }
ModelLibrary >> relationKindCount: aHandle [
	^ self ffiCall: #(uint64 model_relation_kind_count (void * aHandle))
]

{ #category : 'ffi' }
ModelLibrary >> relationKindNames: aHandle [
	^ self ffiCall: #(void * model_relation_kind_names (void * aHandle))
]

{ #category : 'ffi' }
ModelLibrary >> relationKinds: aHandle [
	^ self ffiCall: #(void * model_relation_kinds (void * aHandle))
]

{ #category : 'ffi' }
ModelLibrary >> relationSiteOffsets: aHandle [
	^ self ffiCall: #(void * model_relation_site_offsets (void * aHandle))
]

{ #category : 'ffi' }
ModelLibrary >> relationTo: aHandle [
	^ self ffiCall: #(void * model_relation_to (void * aHandle))
]

{ #category : 'ffi' }
ModelLibrary >> siteCount: aHandle [
	^ self ffiCall: #(uint64 model_site_count (void * aHandle))
]

{ #category : 'ffi' }
ModelLibrary >> siteFlags: aHandle [
	^ self ffiCall: #(void * model_site_flags (void * aHandle))
]

{ #category : 'ffi' }
ModelLibrary >> siteRanges: aHandle [
	^ self ffiCall: #(void * model_site_ranges (void * aHandle))
]

{ #category : 'reading' }
ModelLibrary >> stringColumn: aPointer count: n [
	"Reads a column of StrRef { ptr; u32 len } (16 bytes); an absent string is nil."

	^ (1 to: n) collect: [ :i |
			  | offset ptr len bytes |
			  offset := i - 1 * 16.
			  ptr := aPointer pointerAtOffset: offset.
			  len := aPointer unsignedLongAt: offset + 9.
			  ptr isNull
				  ifTrue: [ nil ]
				  ifFalse: [
						  bytes := ByteArray new: len.
						  len > 0 ifTrue: [ LibC memCopy: ptr to: bytes size: len ].
						  bytes utf8Decoded ] ]
]

{ #category : 'reading' }
ModelLibrary >> uint32Column: aPointer count: n [
	"Copies a u32 column; u32::MAX (absent) is mapped to nil."

	| bytes |
	n = 0 ifTrue: [ ^ #(  ) ].
	bytes := ByteArray new: n * 4.
	LibC memCopy: aPointer to: bytes size: n * 4.
	^ (1 to: n) collect: [ :i |
			  | v |
			  v := bytes unsignedLongAt: i - 1 * 4 + 1.
			  v = 4294967295
				  ifTrue: [ nil ]
				  ifFalse: [ v ] ]
]

{ #category : 'reading' }
ModelLibrary >> uint8Column: aPointer count: n [

	| bytes |
	n = 0 ifTrue: [ ^ #(  ) ].
	bytes := ByteArray new: n.
	LibC memCopy: aPointer to: bytes size: n.
	^ bytes asArray
]

{ #category : 'accessing platform' }
ModelLibrary >> unix64LibraryName [

	^ self class libraryPath
]

{ #category : 'accessing platform' }
ModelLibrary >> win32LibraryName [

	^ self class libraryPath
]
