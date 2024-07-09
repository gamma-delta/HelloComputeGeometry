class_name ComputeGeometryOrchestrator extends RefCounted

# The main logic goes here.
# The script on the RootNode changes the mesh input on number keys

var mesh_displayer : MeshInstance3D

# Handy pointer to the main rendering device
var rd : RenderingDevice
# To avoid having a billion variables everywhere, all the RIDs are stored in here
var compute_stuff := {}

var in_buf_scratch := PackedByteArray()
var shader_texture : Texture2DRD

var mesh_in_dirty := false
var queued_push_data := PackedByteArray()
var texture_size : int
var actual_tri_count : int

# constants across the life of the object
var max_triangles : int
var max_generated_tris_per_tri : int

const SIZE_OF_FLOAT := 4
const SIZE_OF_VERTEX := 12 * SIZE_OF_FLOAT
const SIZE_OF_TRI := SIZE_OF_VERTEX * 3

func _init(mesh_displayer: MeshInstance3D, max_triangles: int, max_generated_tris_per_tri: int) -> void:
  self.mesh_displayer = mesh_displayer
  self.max_triangles = max_triangles
  self.max_generated_tris_per_tri = max_generated_tris_per_tri
  
  var max_out_tris := max_triangles * max_generated_tris_per_tri
  var max_out_v4s := max_out_tris * 9
  self.texture_size = ceili(sqrt(max_out_v4s))
  # self.texture_size = 1024
  
  print("texture size: ", self.texture_size)
  var shader_mat := load("res://shaders/unpack_verts_from_compute.tres")
  mesh_displayer.material_override = shader_mat
  self.shader_texture = Texture2DRD.new()
  shader_mat.set_shader_parameter("data_in", self.shader_texture)

func submit_base_mesh(mesh: Mesh) -> void:
  self.actual_tri_count = format_mesh(mesh, self.in_buf_scratch)
  print("triangles: ", self.actual_tri_count)
  if self.actual_tri_count > self.max_triangles:
    push_error("Too many triangles! This mesh has ", 
        self.actual_tri_count, "but only set up to handle ", self.max_triangles)
    # This is a totally solvable problem;
    # for example every time you got more triangles than you could handle
    # you could reallocate the buffer & out image to be as big as you needed,
    # or twice as big, or whatever.
    # Sending the data to the GPU is pretty fast these days. 
  self.mesh_in_dirty = true

func draw():
  if self.rd == null:
    # Some of this setup apparently has to be done once it's ready to draw,
    # not in init. beats me
    RenderingServer.call_on_render_thread(self._init_gpu)
  
  RenderingServer.call_on_render_thread(self._compute_frame)
  self.mesh_in_dirty = false

func _init_gpu():
  self.rd = RenderingServer.get_rendering_device()

  var shader_file := load("res://shaders/write_triangles.glsl")
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
  
  # First uniform: a storage buffer of our vertices
  var in_buf_uniform := RDUniform.new()
  in_buf_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
  in_buf_uniform.binding = 0 # lines up with the binding=0 in the glsl
  in_buf_uniform.add_id(in_buf_rid)
  # Second uniform: the texture we write our vertex data to
  var out_tex_uniform := RDUniform.new()
  out_tex_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
  out_tex_uniform.binding = 1
  out_tex_uniform.add_id(out_tex_rid)
  # We want to be able to count the number of triangles every invocation has written altogether
  # For that, we use an atomic! Or rather we use atomic operations on an int.
  # This is the CounterBuffer in the glsl.
  # It has to be a separate buffer so it can be read/write
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
      
  # This is the "Secret sauce"
  # This makes the Godot texture read from the .gdshader and the GLSL texture
  # written from the .compute.glsl be the same image
  self.shader_texture.texture_rd_rid = self.compute_stuff["out_tex_rid"]

  self.mesh_displayer.mesh = self._make_dummy_arraymesh()

func _compute_frame():
  if self.mesh_in_dirty:
    # We have to clear the entire input vertex buffer, otherwise old triangles will be left over,
    # because buffer_update only overwrites as many bytes as is given.
    # I'm not sure if this is slow; possibly you could extend in_buf_scratch to be the size
    # of the whole GPU-side buffer and do it all in one operation
    rd.buffer_clear(self.compute_stuff["in_buf_rid"], 0, self.max_triangles * SIZE_OF_TRI)
    rd.buffer_update(self.compute_stuff["in_buf_rid"], 0, self.in_buf_scratch.size(), self.in_buf_scratch)
  # reset counter
  rd.buffer_update(self.compute_stuff["atomics_at_home_rid"], 0, 4, PackedByteArray([0, 0, 0, 0]))
  # reset output texture
  # transparent = all zeroes
  rd.texture_clear(self.compute_stuff["out_tex_rid"], Color.TRANSPARENT, 0, 1, 0, 1)
  
  # Write the "push list" data, which is a way to send a small amount of data to the GPU
  # without needing a uniform.
  # https://vkguide.dev/docs/chapter-3/push_constants/
  # This corresponds with the push_constant block in the glsl file
  var push_list := ByteWriter.new()
  push_list.write_int(self.texture_size)
  push_list.write_int(self.texture_size)
  push_list.write_int(self.max_generated_tris_per_tri)
  # turns out that Time.get_unix_time_from_system just straight-up doesn't work     
  push_list.write_float(Time.get_ticks_msec() / 1000.0)

  # set up the computation!
  var compute_list := rd.compute_list_begin()
  # boring stuff
  rd.compute_list_bind_compute_pipeline(compute_list, self.compute_stuff["pipeline"])
  rd.compute_list_bind_uniform_set(compute_list, self.compute_stuff["uniform_set"], 0)
  rd.compute_list_set_push_constant(compute_list, push_list.inner, push_list.size())
  # set up the dispatch!
  # In the shader, I've set up a local size of 32
  # this means every workgroup processes 32 triangles
  var needed_dispatch_count : int = self.max_triangles / 32
  rd.compute_list_dispatch(compute_list, needed_dispatch_count, 1, 1)
  rd.compute_list_end()

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

func _display_mat() -> ShaderMaterial:
  return self.mesh_displayer.material_override as ShaderMaterial

# Returns the number of triangles found
static func format_mesh(mesh: Mesh, tris_buf: PackedByteArray) -> int:
  var surf1 := mesh.surface_get_arrays(0)
  var vertices : PackedVector3Array = surf1[Mesh.ARRAY_VERTEX]
  var normals : PackedVector3Array = surf1[Mesh.ARRAY_NORMAL]
  var has_uvs := surf1[Mesh.ARRAY_TEX_UV] != null
  var uvs : PackedVector2Array = surf1[Mesh.ARRAY_TEX_UV] if has_uvs else PackedVector2Array()
  var indices : PackedInt32Array = surf1[Mesh.ARRAY_INDEX]
  
  tris_buf.clear()
  # we have to de-index the array here.
  for i in range(0, indices.size()):
    var index := indices[i]
    var vert := vertices[index]
    var norm := normals[index]
    var uv := uvs[index] if has_uvs else Vector2.ZERO

    # Must be laid out the same as in the glsl
    var float_arr := PackedFloat32Array([
      vert.x, vert.y, vert.z, 0.0,
      norm.x, norm.y, norm.z, 0.0,
      uv.x, uv.y,
      0.0, 0.0])
    tris_buf.append_array(float_arr.to_byte_array())
  
  return indices.size() / 3
