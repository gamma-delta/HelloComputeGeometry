extends Node3D

@export var MY_MESH : Mesh

var rd : RenderingDevice
var shader_rid : RID
var in_buf_rid : RID
var out_buf_rid : RID
var misc_buf_rid : RID
var uniform_set : RID
var pipeline : RID

var in_buf_scratch := PackedByteArray()
var out_buf_scratch := PackedByteArray()

const SIZE_OF_FLOAT := 4
const SIZE_OF_VERTEX := 8 * SIZE_OF_FLOAT
const SIZE_OF_TRI := SIZE_OF_VERTEX * 3 + 4 * SIZE_OF_FLOAT
const MAX_GENERATED_TRIS_PER_TRI := 1

# Called when the node enters the scene tree for the first time.
func _ready():
  pass

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
  if self.rd == null:
    self.init_gpu()
  
  var mesh_data := self.format_mesh(self.MY_MESH)
  rd.buffer_update(self.in_buf_rid, 0, self.in_buf_scratch.size(), self.in_buf_scratch)
  var misc_buf := PackedByteArray()
  misc_buf.append_array(PackedFloat32Array([Time.get_unix_time_from_system()]).to_byte_array())
  rd.buffer_update(self.misc_buf_rid, 0, misc_buf.size(), misc_buf)
  
  var compute_list := rd.compute_list_begin()
  rd.compute_list_bind_compute_pipeline(compute_list, self.pipeline)
  rd.compute_list_bind_uniform_set(compute_list, self.uniform_set, 0)
  # set up the dispatch!
  # In the shader, I've set up a local size of 32
  var needed_dispatch_count : int = mesh_data["tri_count"] / 32
  rd.compute_list_dispatch(compute_list, needed_dispatch_count, 1, 1)
  rd.compute_list_end()
  
  rd.submit()
  rd.sync()
  
  # TODO: is there a way to do this without transferring the data back to the CPU?
  self.out_buf_scratch = rd.buffer_get_data(self.out_buf_rid)
  var out_bytes := ByteBuf.new(self.out_buf_scratch)
  #print("gpu returned bytes:", out_bytes.size())
  var array_mesh = $MeshInstance3D.mesh as ArrayMesh
  
  var new_verts := PackedVector3Array()
  var new_norms := PackedVector3Array()
  var new_uvs := PackedVector2Array()

  while !out_bytes.finished():
    var tri_normal := out_bytes.read_vec3_opengl()
    for i in range(0, 3):
      new_verts.push_back(out_bytes.read_vec3_opengl()) # XYZ
      new_uvs.push_back(out_bytes.read_vec2()) # UV
      out_bytes.read_vec2() # scratch
      # Push the normal, thrice
      new_norms.push_back(tri_normal)
  
  array_mesh.clear_surfaces()
  var surf_arrays := []
  surf_arrays.resize(Mesh.ARRAY_MAX)
  surf_arrays[Mesh.ARRAY_VERTEX] = new_verts
  surf_arrays[Mesh.ARRAY_NORMAL] = new_norms
  surf_arrays[Mesh.ARRAY_TEX_UV] = new_uvs
  print("received ", new_verts.size(), " vertices from the gpu")
  array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surf_arrays)

func init_gpu():
  self.rd = RenderingServer.create_local_rendering_device()
  var shader_file := load("res://pyramidize.glsl")
  var shader_spirv : RDShaderSPIRV = shader_file.get_spirv()
  self.shader_rid = rd.shader_create_from_spirv(shader_spirv)
  
  var format := self.format_mesh(self.MY_MESH)
  self.in_buf_rid = self.rd.storage_buffer_create(self.in_buf_scratch.size(), self.in_buf_scratch)
  self.out_buf_rid = self.rd.storage_buffer_create(self.out_buf_scratch.size(), self.out_buf_scratch)
  self.misc_buf_rid = self.rd.storage_buffer_create(4)
  
  var in_buf_uniform := RDUniform.new()
  in_buf_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
  in_buf_uniform.binding = 0 # lines up with the binding=0 in the glsl
  in_buf_uniform.add_id(self.in_buf_rid)
  var out_buf_uniform := RDUniform.new()
  out_buf_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
  out_buf_uniform.binding = 1
  out_buf_uniform.add_id(self.out_buf_rid)
  var misc_buf_uniform := RDUniform.new()
  misc_buf_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
  misc_buf_uniform.binding = 2
  misc_buf_uniform.add_id(self.misc_buf_rid)
  
  # the 0 lines up with the set=0 in glsl
  self.uniform_set = rd.uniform_set_create([
    in_buf_uniform, out_buf_uniform, misc_buf_uniform
  ], self.shader_rid, 0)
  self.pipeline = rd.compute_pipeline_create(self.shader_rid)

func format_mesh(mesh: Mesh) -> Dictionary:
  var surf1 := mesh.surface_get_arrays(0)
  var vertices : PackedVector3Array = surf1[Mesh.ARRAY_VERTEX]
  var normals : PackedVector3Array = surf1[Mesh.ARRAY_NORMAL]  
  var uvs : PackedVector2Array = surf1[Mesh.ARRAY_TEX_UV]
  var indices : PackedInt32Array = surf1[Mesh.ARRAY_INDEX]
  print("mesh vert count:", vertices.size(), "; idx count:", indices.size())
  
  self.in_buf_scratch.clear()
  # we have to de-index the array here.
  for i in range(0, indices.size() / 3):
    # Output triangles at a time.
    var tri_bytes := PackedByteArray()
    # each triangle has 1 normal, but I guess not to godot
    var avg_normal := Vector3.ZERO
    for j in range(0, 3):
      var idx_index = i * 3 + j
      var index := indices[idx_index]
      var vert := vertices[index]
      var norm := normals[index]
      var uv := uvs[index]
      
      # Must be laid out the same as in the glsl
      var float_arr := PackedFloat32Array([
        vert.x, vert.y, vert.z, 0.0,
        uv.x, uv.y,
        0.0, 0.0])
      tri_bytes.append_array(float_arr.to_byte_array())
      avg_normal += norm
      
    avg_normal /= 3.0
    self.in_buf_scratch.append_array(PackedFloat32Array([
      avg_normal.x, avg_normal.y, avg_normal.z, 0.0
    ]).to_byte_array())
    self.in_buf_scratch.append_array(tri_bytes)
  
  self.out_buf_scratch.clear()
  self.out_buf_scratch.resize(self.in_buf_scratch.size() * MAX_GENERATED_TRIS_PER_TRI)
  return {"tri_count" = indices.size() / 3}
