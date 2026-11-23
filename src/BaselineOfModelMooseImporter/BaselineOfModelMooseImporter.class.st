Class {
	#name : 'BaselineOfModelMooseImporter',
	#superclass : 'BaselineOf',
	#category : 'BaselineOfModelMooseImporter',
	#package : 'BaselineOfModelMooseImporter'
}

{ #category : 'baselines' }
BaselineOfModelMooseImporter >> baseline: spec [

	<baseline>
	self defineDependencies: spec.
	self definePackages: spec.
	self defineGroups: spec
]

{ #category : 'baselines' }
BaselineOfModelMooseImporter >> defineDependencies: spec [

]

{ #category : 'baselines' }
BaselineOfModelMooseImporter >> defineGroups: spec [
]

{ #category : 'baselines' }
BaselineOfModelMooseImporter >> definePackages: spec [
	"common"

	spec package: 'Model-Moose-Importer'
]
