"
Imports a Model (via model-ffi, no JSON) into a Famix model. Mapping from Model kind names to FM3 classes is data (kindClassNames); containers are found through the FM3 metamodel of the target. Usage: ModelImporter new prefix: 'FamixJava'; importModelAt: 'model.json' into: FamixJavaModel new sourceRoot: '/path/to/sources'.
"
Class {
	#name : 'ModelImporter',
	#superclass : 'Object',
	#instVars : [
		'lib',
		'famixModel',
		'prefix',
		'sourceRoot',
		'n',
		'names',
		'files',
		'parents',
		'kinds',
		'flags',
		'ranges',
		'kindNames',
		'relFrom',
		'relTo',
		'relKinds',
		'siteOffsets',
		'siteRanges',
		'siteFlags',
		'relKindNames',
		'entities',
		'associations',
		'anchorQueue',
		'containerCache',
		'skipped',
		'acceptCache',
		'kindArchetypes',
		'fileTypes',
		'buildReport'
	],
	#category : 'Model-Moose-Importer',
	#package : 'Model-Moose-Importer'
}

{ #category : 'importing' }
ModelImporter >> accepts: anEntity as: aPropertyName of: anAssociationClass [
	"Does the FM3 type of that property accept the entity? A property unknown to the metamodel does not reject."

	acceptCache ifNil: [ acceptCache := Dictionary new ].
	^ acceptCache
		  at: {
				  anAssociationClass.
				  aPropertyName.
				  anEntity class }
		  ifAbsentPut: [
				  (famixModel metamodel fmTypeOf: anAssociationClass)
					  allProperties
					  detect: [ :p | p name = aPropertyName ]
					  ifFound: [ :p |
							  | t |
							  t := p type implementingClass.
							  (anEntity class includesBehavior: t) or: [
								  anEntity class allTraits includes: t ] ]
					  ifNone: [ true ] ]
]

{ #category : 'importing' }
ModelImporter >> associationSpecFor: aKind from: from to: to [
	"{ simple FM3 class. from property. to property (for the FM3 type check) } or nil when the kind has no association."

	| implements |
	aKind = 'calls' ifTrue: [ ^ #( 'Invocation' #sender #candidates ) ].
	aKind = 'accesses' ifTrue: [ ^ #( 'Access' #accessor #candidates ) ].
	aKind = 'declared_type' ifTrue: [
		^ #( 'EntityTyping' #typedEntity #declaredType ) ].
	aKind = 'references' ifTrue: [
		^ #( 'Reference' #referencer #referredEntity ) ].
	aKind = 'imports' ifTrue: [
		^ #( 'Import' #importingEntity #importedEntity ) ].
	(aKind = 'inherits' or: [ aKind = 'implements' ]) ifTrue: [
			implements := (self isInterfaceLike: to) and: [
					              (self isInterfaceLike: from) not and: [
						              from class name ~= (prefix , 'Enum') asSymbol ] ].
			^ implements
				  ifTrue: [ #( 'Implementation' #implementingClass
				     #interface ) ]
				  ifFalse: [ #( 'Inheritance' #subclass #superclass ) ] ].
	^ nil
]

{ #category : 'importing' }
ModelImporter >> buildReport [
	"Counts and warnings of the build when the model was built from sources, '' otherwise."

	^ buildReport ifNil: [ '' ]
]

{ #category : 'importing' }
ModelImporter >> classNamed: aSimpleName [

	^ Smalltalk at: (prefix , aSimpleName) asSymbol
]

{ #category : 'importing' }
ModelImporter >> computeFileTypes [

	fileTypes := Dictionary new.
	1 to: n do: [ :i |
			| entity file parent |
			entity := entities at: i.
			file := files at: i.
			(entity notNil and: [
					 file notNil and: [
							 ((flags at: i) bitAnd: 1) = 0 and: [
									 (self isNamed: 'Class' in: entity) or: [
											 (self isNamed: 'Interface' in: entity) or: [
													 (self isNamed: 'Enum' in: entity) or: [
														 self isNamed: 'AnnotationType' in: entity ] ] ] ] ] ])
				ifTrue: [
						parent := (parents at: i) ifNotNil: [ :p | entities at: p + 1 ].
						(parent notNil and: [
							 (self isTypeEntity: parent) or: [
								 self isNamed: 'Method' in: parent ] ]) ifFalse: [
							fileTypes at: file ifAbsentPut: [ i ] ] ] ]
]

{ #category : 'importing' }
ModelImporter >> containerSelectorFor: child parent: parent [

	^ containerCache
		  at: {
				  child class.
				  parent class }
		  ifAbsentPut: [
				  | simple |
				  simple := (child class name allButFirst: prefix size) asString.
				  (self preferredContainers at: simple ifAbsent: [ nil ])
					  ifNotNil: [ :property | (property , ':') asSymbol ]
					  ifNil: [
							  (famixModel metamodel fmTypeOf: child class) allProperties
								  detect: [ :p |
										  p isContainer and: [
												  | t |
												  t := p type implementingClass.
												  (parent class includesBehavior: t) or: [
													  parent class allTraits includes: t ] ] ]
								  ifFound: [ :p | (p implementingSelector , ':') asSymbol ]
								  ifNone: [ nil ] ] ]
]

{ #category : 'importing' }
ModelImporter >> createAssociations [

	1 to: relFrom size do: [ :r |
			| fromIndex source from to kind |
			fromIndex := (relFrom at: r) + 1.
			kind := relKindNames at: (relKinds at: r) + 1.
			source := self sourceIndexFor: kind from: fromIndex.
			from := source ifNotNil: [ entities at: source ].
			to := entities at: (relTo at: r) + 1.
			(from isNil or: [ to isNil ])
				ifTrue: [ self skip: kind ]
				ifFalse: [
						(siteOffsets at: r) + 1 to: (siteOffsets at: r + 1) do: [ :s |
								| assoc |
								assoc := self
									         newAssociationOf: kind
									         from: from
									         to: to
									         flags: (siteFlags at: s).
								assoc ifNil: [ self skip: kind ] ifNotNil: [
										associations add: assoc.
										"As the Moose exporter: a typing has no anchor; the site is in the file of the original source."
										kind = 'declared_type' ifFalse: [
												self
													queue: assoc
													file: (self fileOf: fromIndex)
													range: (siteRanges copyFrom: s - 1 * 4 + 1 to: s * 4) ] ] ] ] ]
]

{ #category : 'importing' }
ModelImporter >> createEntities [

	| classNames |
	classNames := self kindClassNames.
	entities := Array new: n.
	1 to: n do: [ :i |
			| simple class entity |
			simple := classNames
				          at: (kindNames at: (kinds at: i) + 1)
				          ifAbsent: [ nil ].
			class := simple ifNotNil: [
				         Smalltalk
					         at: (prefix , simple) asSymbol
					         ifAbsent: [ nil ] ].
			class ifNotNil: [
					entity := class new.
					(entity respondsTo: #name:) ifTrue: [ entity name: (names at: i) ].
					(((flags at: i) bitAnd: 1) ~= 0 and: [
						 entity respondsTo: #isStub: ]) ifTrue: [ entity isStub: true ].
					entities at: i put: entity ] ]
]

{ #category : 'importing' }
ModelImporter >> fileOf: anIndex [
	"File of the entity, or of its closest ancestor that has one."

	| i |
	i := anIndex.
	[ i notNil ] whileTrue: [
			(files at: i) ifNotNil: [ :f | ^ f ].
			i := (parents at: i) ifNotNil: [ :p | p + 1 ] ].
	^ nil
]

{ #category : 'importing' }
ModelImporter >> importInto: aFamixModel sourceRoot: aRoot opening: aBlock [

	| h |
	lib := ModelLibrary uniqueInstance.
	famixModel := aFamixModel.
	sourceRoot := aRoot asFileReference.
	h := aBlock value: lib.
	h isNull ifTrue: [ ^ self error: lib lastError ].
	buildReport := lib buildReportOf: h.
	[ self readColumns: h ] ensure: [ lib free: h ].
	containerCache := Dictionary new.
	skipped := Dictionary new.
	associations := OrderedCollection new.
	anchorQueue := Dictionary new.
	self createEntities.
	self linkContainers.
	self computeFileTypes.
	self queueEntityAnchors.
	self createAssociations.
	self resolveAnchors.
	famixModel silentlyAddAll: (entities select: #notNil) , associations.
	^ self report
]

{ #category : 'importing' }
ModelImporter >> importModelAt: aPath into: aFamixModel sourceRoot: aRoot [
	"From a model.json written by Model."

	^ self
		  importInto: aFamixModel
		  sourceRoot: aRoot
		  opening: [ :library | library open: aPath asString ]
]

{ #category : 'importing' }
ModelImporter >> importSourcesAt: aRoot into: aFamixModel [
	"Builds the model of the sources in-process (tree-sitter only) and imports it: no JSON."

	^ self
		  importSourcesAt: aRoot
		  into: aFamixModel
		  scip: false
		  reindex: 0
		  languages: ''
		  scope: ''
]

{ #category : 'importing' }
ModelImporter >> importSourcesAt: aRoot into: aFamixModel scip: useScip reindex: aReindexCode languages: aLanguageList scope: aScopeList [
	"As importSourcesAt:into:, choosing the build: useScip uses SCIP indexes; aReindexCode 0 never, 1 if missing, 2 if stale, 3 always (anything but 0 may run an indexer, i.e. the project's build tool); the lists are comma-separated, empty for all. The call blocks until the build is done."

	| root |
	root := aRoot asFileReference pathString.
	^ self
		  importInto: aFamixModel
		  sourceRoot: root
		  opening: [ :library |
				  library hasBuild = 1 ifFalse: [
						  self error:
							  'libmodel_ffi was built without the build feature (cargo build --release -p model-ffi --features build)' ].
				  library
					  build: root
					  scip: (useScip
							   ifTrue: [ 1 ]
							   ifFalse: [ 0 ])
					  reindex: aReindexCode
					  languages: aLanguageList
					  scope: aScopeList ]
]

{ #category : 'importing' }
ModelImporter >> importerIndexOf: anIndex [
	"An import is made by the first top-level type of the file when the source is the file itself."

	(entities at: anIndex) ifNotNil: [ ^ anIndex ].
	^ fileTypes
		  at: ((files at: anIndex) ifNil: [ names at: anIndex ])
		  ifAbsent: [ nil ]
]

{ #category : 'importing' }
ModelImporter >> isCallableAt: anIndex [

	^ #( 'method' 'constructor' 'function' ) includes:
		  (kindArchetypes at: (kinds at: anIndex) + 1)
]

{ #category : 'importing' }
ModelImporter >> isInterfaceLike: anEntity [

	^ {
		  (prefix , 'Interface') asSymbol.
		  (prefix , 'AnnotationType') asSymbol } includes:
		  anEntity class name
]

{ #category : 'importing' }
ModelImporter >> isNamed: aSimpleName in: anEntity [

	^ anEntity class name = (prefix , aSimpleName) asSymbol
]

{ #category : 'importing' }
ModelImporter >> isTypeEntity: anEntity [
	"A type as Famix associations target it (typing, reference); the FM3 traits of some types (interfaces) do not say so."

	^ #( 'Class' 'Interface' 'Enum' 'AnnotationType' 'TypeParameter' )
		  anySatisfy: [ :simple | self isNamed: simple in: anEntity ]
]

{ #category : 'accessing' }
ModelImporter >> kindClassNames [
	"Model kind name -> simple FM3 class name. Data, per target language family."

	^ Dictionary newFromPairs:
		  #( 'namespace' 'Package' 'class' 'Class' 'record' 'Class' 'interface'
		     'Interface' 'annotation_type' 'AnnotationType' 'enum' 'Enum'
		     'method' 'Method' 'constructor' 'Method' 'field' 'Attribute'
		     'constant' 'Attribute' 'enum_constant' 'EnumValue' 'parameter'
		     'Parameter' 'local_variable' 'LocalVariable' 'type_parameter'
		     'TypeParameter' 'annotation' 'AnnotationInstance'
		     'comment' 'Comment' )
]

{ #category : 'importing' }
ModelImporter >> linkContainers [

	1 to: n do: [ :i |
			| child parentIndex parent selector |
			child := entities at: i.
			parentIndex := parents at: i.
			(child notNil and: [ parentIndex notNil ]) ifTrue: [
					parent := entities at: parentIndex + 1.
					parent ifNotNil: [
							selector := self containerSelectorFor: child parent: parent.
							selector ifNotNil: [ child perform: selector with: parent ] ] ] ]
]

{ #category : 'importing' }
ModelImporter >> newAssociationOf: aKind from: from to: to flags: aFlagByte [

	| spec class toOk |
	spec := self associationSpecFor: aKind from: from to: to.
	spec ifNil: [ ^ nil ].
	class := self classNamed: spec first.
	toOk := (#( declaredType referredEntity ) includes: spec third)
		        ifTrue: [ self isTypeEntity: to ]
		        ifFalse: [ self accepts: to as: spec third of: class ].
	((self accepts: from as: spec second of: class) and: [ toOk ])
		ifFalse: [ ^ nil ].
	spec first = 'Invocation' ifTrue: [
			^ class new
				  sender: from;
				  addCandidate: to;
				  yourself ].
	spec first = 'Access' ifTrue: [
			^ class new
				  accessor: from;
				  variable: to;
				  isWrite: (aFlagByte bitAnd: 2) ~= 0;
				  yourself ].
	spec first = 'EntityTyping' ifTrue: [
			^ class new
				  typedEntity: from;
				  declaredType: to;
				  yourself ].
	spec first = 'Reference' ifTrue: [
			^ class new
				  referencer: from;
				  referredEntity: to;
				  yourself ].
	spec first = 'Import' ifTrue: [
			^ class new
				  importingEntity: from;
				  importedEntity: to;
				  yourself ].
	spec first = 'Implementation' ifTrue: [
			^ class new
				  implementingClass: from;
				  interface: to;
				  yourself ].
	^ class new
		  subclass: from;
		  superclass: to;
		  yourself
]

{ #category : 'importing' }
ModelImporter >> ownerIndexOf: anIndex [
	"The entity (or its nearest callable ancestor) that sends calls and makes accesses."

	| i |
	((entities at: anIndex) notNil and: [ self isCallableAt: anIndex ])
		ifTrue: [ ^ anIndex ].
	i := parents at: anIndex.
	[ i notNil ] whileTrue: [
			((entities at: i + 1) notNil and: [ self isCallableAt: i + 1 ])
				ifTrue: [ ^ i + 1 ].
			i := parents at: i + 1 ].
	^ (entities at: anIndex) ifNotNil: [ anIndex ]
]

{ #category : 'importing' }
ModelImporter >> preferredContainers [
	"Simple FM3 class name -> container property, when the FM3 types alone are ambiguous. Mirrors what the Moose exporter writes (types go in typeContainer); anything else is found through the FM3 metamodel."

	^ Dictionary newFromPairs:
		  #( 'Class' #typeContainer 'Exception' #typeContainer
		     'Interface' #typeContainer 'Enum' #typeContainer 'TypeParameter'
		     #typeContainer )
]

{ #category : 'accessing' }
ModelImporter >> prefix: aString [

	prefix := aString
]

{ #category : 'importing' }
ModelImporter >> queue: anElement file: aFile range: aQuadruple [

	aFile ifNil: [ ^ self skip: 'anchor:no-file' ].
	(anchorQueue at: aFile ifAbsentPut: [ OrderedCollection new ]) add:
		{
			anElement.
			aQuadruple }
]

{ #category : 'importing' }
ModelImporter >> queueEntityAnchors [

	1 to: n do: [ :i |
			((entities at: i) notNil and: [ ((flags at: i) bitAnd: 2) ~= 0 ])
				ifTrue: [
						self
							queue: (entities at: i)
							file: (files at: i)
							range: (ranges copyFrom: i - 1 * 4 + 1 to: i * 4) ] ]
]

{ #category : 'importing' }
ModelImporter >> readColumns: h [

	| relCount siteCount kindCount relKindCount |
	n := lib entityCount: h.
	relCount := lib relationCount: h.
	siteCount := lib siteCount: h.
	kindCount := lib kindCount: h.
	relKindCount := lib relationKindCount: h.
	names := lib stringColumn: (lib entityNames: h) count: n.
	files := lib stringColumn: (lib entityFiles: h) count: n.
	parents := lib uint32Column: (lib entityParents: h) count: n.
	kinds := lib uint32Column: (lib entityKinds: h) count: n.
	flags := lib uint32Column: (lib entityFlags: h) count: n.
	ranges := lib uint32Column: (lib entityRanges: h) count: n * 4.
	kindNames := lib stringColumn: (lib kindNames: h) count: kindCount.
	kindArchetypes := lib
		                  stringColumn: (lib kindArchetypes: h)
		                  count: kindCount.
	relFrom := lib uint32Column: (lib relationFrom: h) count: relCount.
	relTo := lib uint32Column: (lib relationTo: h) count: relCount.
	relKinds := lib uint32Column: (lib relationKinds: h) count: relCount.
	siteOffsets := lib
		               uint32Column: (lib relationSiteOffsets: h)
		               count: relCount + 1.
	siteRanges := lib
		              uint32Column: (lib siteRanges: h)
		              count: siteCount * 4.
	siteFlags := lib uint8Column: (lib siteFlags: h) count: siteCount.
	relKindNames := lib
		                stringColumn: (lib relationKindNames: h)
		                count: relKindCount
]

{ #category : 'accessing' }
ModelImporter >> report [

	^ {
		  (#entities -> (entities count: #notNil)).
		  (#associations -> associations size).
		  (#skippedRelations -> skipped) }
]

{ #category : 'importing' }
ModelImporter >> resolveAnchors [

	anchorQueue keysAndValuesDo: [ :file :items |
			| path spans |
			path := (sourceRoot resolve: file) pathString.
			spans := lib charOffsetsIn: path ranges: (items collect: #second).
			spans ifNil: [ self skip: 'anchor:unreadable-file' ] ifNotNil: [
					items with: spans do: [ :item :span |
							| anchor |
							anchor := (self classNamed: 'IndexedFileAnchor') new
								          fileName: path;
								          startPos: span first;
								          endPos: span last;
								          yourself.
							item first sourceAnchor: anchor.
							associations add: anchor ] ] ]
]

{ #category : 'importing' }
ModelImporter >> skip: aKey [

	skipped at: aKey update: [ :c | c + 1 ] initial: [ 1 ]
]

{ #category : 'importing' }
ModelImporter >> sourceIndexFor: aKind from: anIndex [

	(#( 'calls' 'accesses' 'references' ) includes: aKind) ifTrue: [
		^ self ownerIndexOf: anIndex ].
	aKind = 'imports' ifTrue: [ ^ self importerIndexOf: anIndex ].
	^ (entities at: anIndex) ifNotNil: [ anIndex ]
]
