package tinyobjloader

import "core:c"

foreign import tinyobjloader "tinyobjloader.lib"

FLAG_TRIANGULATE :: 1 << 0
INVALID_INDEX :: 0x80000000

SUCCESS :: 0
ERROR_EMPTY :: -1
ERROR_INVALID_PARAMETER :: -2
ERROR_FILE_OPERATION :: -3

attrib_t :: struct {
	num_vertices: c.uint,
	num_normals: c.uint,
	num_texcoords: c.uint,
	num_faces: c.uint,
	num_face_num_verts: c.uint,

	_: c.int,

	vertices: [^]c.float,
	normals: [^]c.float,
	texcoords: [^]c.float,
	faces: [^]vertex_index_t,
	face_num_verts: ^c.int,
	material_ids: [^]c.int,
}

vertex_index_t :: struct {
	v_idx: c.int,
	vt_idx: c.int,
	vn_idx: c.int,
}

shape_t :: struct {
	name: cstring,
	face_offset: c.uint,
	length: c.uint,
}

material_t :: struct {
	name: cstring,

	ambient: [3]c.float,
	diffuse: [3]c.float,
	specular: [3]c.float,
	transmittance: [3]c.float,
	emission: [3]c.float,
	shininess: c.float,
	ior: c.float,
	dissolve: c.float,
	illum: c.int,

	_: c.int,

	ambient_texname: cstring,
	diffuse_texname: cstring,
	specular_texname: cstring,
	specular_highlight_texname: cstring,
	bump_texname: cstring,
	displacement_texname: cstring,
	alpha_texname: cstring,
}

file_reader_callback :: #type proc "c" (ctx: rawptr,
					filename: cstring,
					is_mtl: c.int,
					obj_filename: cstring,
					buf: ^[^]c.char,
					len: ^c.size_t)

@(default_calling_convention="c", link_prefix="tinyobj_")
foreign tinyobjloader {
	parse_obj :: proc(attrib: ^attrib_t,
			  shapes: ^[^]shape_t,
			  num_shapes: ^c.size_t,
			  materials: ^[^]material_t,
			  num_materials: ^c.size_t,
			  file_name: cstring,
			  file_reader: file_reader_callback,
			  ctx: rawptr,
			  flags: c.uint) -> c.int ---
	attrib_init :: proc(attrib: ^attrib_t) ---
	attrib_free :: proc(attrib: ^attrib_t) ---
	shapes_free :: proc(shapes: [^]shape_t, num_shapes: c.size_t) ---
	materials_free :: proc(materials: [^]material_t, num_materials: c.size_t) ---
}
