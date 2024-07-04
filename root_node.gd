extends Node3D

var cgo : ComputeGeometryOrchestrator

@export var mesh_in : Mesh
@export var mesh_display : MeshInstance3D

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
  self.cgo = ComputeGeometryOrchestrator.new(self.mesh_display, 8192, 16)
  self.cgo.submit_base_mesh(mesh_in)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
  self.cgo.push_data(PackedFloat32Array([Time.get_ticks_msec() / 1000.0]).to_byte_array())
  self.cgo.draw()
