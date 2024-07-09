extends Node3D

var cgo : ComputeGeometryOrchestrator

@export var mesh_displayer : MeshInstance3D
@export var meshes : Array[Mesh]

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
  self.cgo = ComputeGeometryOrchestrator.new(mesh_displayer, 16384, 8)
  self.cgo.submit_base_mesh(meshes[0])

func _input(event: InputEvent) -> void:
  # this is terrible, i know
  if event is InputEventKey and event.is_pressed():
    # between '1' and '9'
    if 0x31 <= event.unicode and event.unicode <= 0x39:
      var number_index = event.unicode - 0x31
      if number_index < self.meshes.size():
        self.cgo.submit_base_mesh(self.meshes[number_index])

func _process(delta: float) -> void:
  self.cgo.draw()
