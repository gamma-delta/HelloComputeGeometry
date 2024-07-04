class_name ComputeGeometryOrchestrator extends RefCounted

var display_mesh : MeshInstance3D
var max_triangles : int
var max_generated_tris_per_tri : int

var rd : RenderingDevice
var compute_stuff := {}
var draw_stuff := {}

var in_buf_scratch := PackedByteArray()
var shader_texture : Texture2DRD

var gpu_state_dirty := false
var queued_push_data := PackedByteArray()
var texture_size : int

const SIZE_OF_FLOAT := 4
const SIZE_OF_VERTEX := 12 * SIZE_OF_FLOAT
const SIZE_OF_TRI := SIZE_OF_VERTEX * 3

func _init(display_mesh: MeshInstance3D, max_triangles: int, max_generated_tris_per_tri: int) -> void:
  self.display_mesh = display_mesh
  self.max_triangles = max_triangles
  self.max_generated_tris_per_tri = max_generated_tris_per_tri
  
  var max_out_tris := max_triangles * max_generated_tris_per_tri
  var max_out_v4s := max_out_tris * 9
  self.texture_size = ceili(sqrt(max_out_v4s))
  # self.texture_size = 1024
  
  print("texture size: ", self.texture_size)
  RenderingServer.call_on_render_thread(self._init_gpu)
  
  var shader_mat := load("res://lib/unpack_verts_from_compute.tres")
  display_mesh.material_override = shader_mat
  self.shader_texture = Texture2DRD.new()
  shader_mat.set_shader_parameter("data_in", self.shader_texture)

func submit_base_mesh(mesh: Mesh) -> void:
  format_mesh(mesh, self.in_buf_scratch)

  # This is the "Secret sauce"
  # This makes the Godot texture read from the .gdshader and the GLSL texture
  # written from the .compute.glsl be the same image
  self.shader_texture.texture_rd_rid = self.compute_stuff["out_tex_rid"]

  self.display_mesh.mesh = self._make_dummy_arraymesh()
  self.gpu_state_dirty = true

func push_data(data: PackedByteArray) -> void:
  self.queued_push_data = data
  self.gpu_state_dirty = true

func draw():
  if self.rd == null:
    RenderingServer.call_on_render_thread(self._init_gpu())
  
  if self.gpu_state_dirty:
    RenderingServer.call_on_render_thread(self._compute_frame)
    self.gpu_state_dirty = false

func _init_gpu():
  self.rd = RenderingServer.get_rendering_device()

  var shader_file := load("res://lib/write_triangles.glsl")
  var shader_spirv : RDShaderSPIRV = shader_file.get_spirv()
  var shader_rid := rd.shader_create_from_spirv(shader_spirv)
  
  # we are going to update this every frame, but we can't init it with an empty buffer
  # also, it has problems reallocating
  # so just give it a huge amount idfc
  self.in_buf_scratch.resize(self.max_triangles * SIZE_OF_TRI)
  var in_buf_rid := self.rd.storage_buffer_create(self.in_buf_scratch.size(), self.in_buf_scratch)
  var atomics_at_home_rid := self.rd.storage_buffer_create(4, PackedByteArray([0, 0, 0, 0]))
  
  var tex_format := RDTextureFormat.new()
  tex_format.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
  tex_format.width = self.texture_size
  tex_format.height = self.texture_size
  tex_format.depth = 1
  #tex_format.texture_type = RenderingDevice.TEXTURE_TYPE_2D
  tex_format.usage_bits = \
      RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT \
    | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT \
    | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT \
    | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT \
    | RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
  tex_format.mipmaps = 1
  tex_format.samples = RenderingDevice.TEXTURE_SAMPLES_1
  var out_tex_rid := self.rd.texture_create(tex_format, RDTextureView.new())
  self.rd.texture_clear(out_tex_rid, Color.TRANSPARENT, 0, 1, 0, 1)
  
  var in_buf_uniform := RDUniform.new()
  in_buf_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
  in_buf_uniform.binding = 0 # lines up with the binding=0 in the glsl
  in_buf_uniform.add_id(in_buf_rid)
  var out_tex_uniform := RDUniform.new()
  out_tex_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
  out_tex_uniform.binding = 1
  out_tex_uniform.add_id(out_tex_rid)
  var atomics_at_home_uniform := RDUniform.new()
  atomics_at_home_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
  atomics_at_home_uniform.binding = 2
  atomics_at_home_uniform.add_id(atomics_at_home_rid)
  
  # the 0 lines up with the set=0 in glsl
  var uniform_set := rd.uniform_set_create([
    in_buf_uniform, out_tex_uniform, atomics_at_home_uniform,
  ], shader_rid, 0)
  var pipeline := rd.compute_pipeline_create(shader_rid)      
  assert(pipeline.is_valid())

  self.compute_stuff["shader_rid"] = shader_rid
  self.compute_stuff["in_buf_rid"] = in_buf_rid
  self.compute_stuff["out_tex_rid"] = out_tex_rid
  self.compute_stuff["atomics_at_home_rid"] = atomics_at_home_rid
  self.compute_stuff["uniform_set"] = uniform_set
  self.compute_stuff["pipeline"] = pipeline

func _compute_frame():
  rd.buffer_update(self.compute_stuff["in_buf_rid"], 0, self.in_buf_scratch.size(), self.in_buf_scratch)
  # reset counter
  rd.buffer_update(self.compute_stuff["atomics_at_home_rid"], 0, 4, PackedByteArray([0, 0, 0, 0]))
  # transparent = all zeroes
  rd.texture_clear(self.compute_stuff["out_tex_rid"], Color.TRANSPARENT, 0, 1, 0, 1)
  
  var push_list := ByteWriter.new()
  push_list.write_int(self.texture_size)
  push_list.write_int(self.texture_size)
  push_list.write_int(self.max_generated_tris_per_tri)
  
  push_list.write_pba(self.queued_push_data)

  var compute_list := rd.compute_list_begin()
  rd.compute_list_bind_compute_pipeline(compute_list, self.compute_stuff["pipeline"])
  rd.compute_list_bind_uniform_set(compute_list, self.compute_stuff["uniform_set"], 0)

  #print(push_list.inner)
  rd.compute_list_set_push_constant(compute_list, push_list.inner, push_list.size())
  # set up the dispatch!
  # In the shader, I've set up a local size of 32
  var needed_dispatch_count : int = self.max_triangles / 32
  rd.compute_list_dispatch(compute_list, needed_dispatch_count, 1, 1)
  rd.compute_list_end()
  
  # rd.barrier(RenderingDevice.BARRIER_MASK_COMPUTE)

# https://github.com/erickweil/GodotTests/blob/38237af0bd88dfcc39ec2480fbb84a674ab7c9e2/ProceduralGeometry/ProceduralGeometry.cs#L123
func _make_dummy_arraymesh():
  var tri_count := self.max_triangles * self.max_generated_tris_per_tri
  var verts := PackedVector3Array()
  # three verts per tri
  for i in range(0, tri_count * 3):
    verts.append(Vector3.ZERO)

  var surfaces := []
  surfaces.resize(ArrayMesh.ARRAY_MAX)
  surfaces[ArrayMesh.ARRAY_VERTEX] = verts
  
  var mesh := ArrayMesh.new()
  mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surfaces)
  return mesh

static func format_mesh(mesh: Mesh, tris_buf: PackedByteArray):
  var surf1 := mesh.surface_get_arrays(0)
  var vertices : PackedVector3Array = surf1[Mesh.ARRAY_VERTEX]
  var normals : PackedVector3Array = surf1[Mesh.ARRAY_NORMAL]  
  var uvs : PackedVector2Array = surf1[Mesh.ARRAY_TEX_UV]
  var indices : PackedInt32Array = surf1[Mesh.ARRAY_INDEX]
  
  tris_buf.clear()
  # we have to de-index the array here.
  for i in range(0, indices.size()):
    var index := indices[i]
    var vert := vertices[index]
    var norm := normals[index]
    var uv := uvs[index]

    # Must be laid out the same as in the glsl
    var float_arr := PackedFloat32Array([
      vert.x, vert.y, vert.z, 0.0,
      norm.x, norm.y, norm.z, 0.0,
      uv.x, uv.y,
      0.0, 0.0])
    tris_buf.append_array(float_arr.to_byte_array())
