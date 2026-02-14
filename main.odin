package vulkan_renderer

import "base:runtime"

import "vendor:glfw"

import "core:log"
import "core:mem"

WINDOW_WIDTH :: 1920
WINDOW_HEIGHT :: 1080
APPLICATION_NAME :: "Renderer"

glfw_error_callback :: proc "c" (error_code: i32, description: cstring) {
	context = g_context
	log.errorf("GLFW Error: %v", description)
}

glfw_framebuffer_size_callback :: proc "c" (window: glfw.WindowHandle, width, height: i32) {
	context = g_context
	renderer := cast(^Renderer)glfw.GetWindowUserPointer(window)
	assert(renderer != nil)
	renderer.should_recreate_swap_chain = true
}

glfw_key_callback :: proc "c" (window: glfw.WindowHandle, key, scancode, action, mods: i32) {
	if key == glfw.KEY_ESCAPE && action == glfw.PRESS do glfw.SetWindowShouldClose(window, true)
}

g_context: runtime.Context

main :: proc() {
	context.logger = log.create_console_logger(.Debug when ODIN_DEBUG else .Info)
	defer log.destroy_console_logger(context.logger)

	when ODIN_DEBUG {
		tracking_allocator: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking_allocator, context.allocator)
		context.allocator = mem.tracking_allocator(&tracking_allocator)

		defer {
			if len(tracking_allocator.allocation_map) > 0 {
				log.errorf("MEMORY LEAK: %v allocations not freed:",
					   len(tracking_allocator.allocation_map))

				for _, entry in tracking_allocator.allocation_map {
					log.errorf("- %v bytes at %v", entry.size, entry.location)
				}
			}

			mem.tracking_allocator_destroy(&tracking_allocator)
		}
	}

	g_context = context

	glfw.SetErrorCallback(glfw_error_callback)

	if !glfw.Init() do log.panic("Failed to initialize glfw!")
	defer glfw.Terminate()

	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)

	window := glfw.CreateWindow(WINDOW_WIDTH, WINDOW_HEIGHT, APPLICATION_NAME, nil, nil)
	if window == nil do log.panic("Failed to create a window!")
	defer glfw.DestroyWindow(window)

	renderer: Renderer
	if !init_renderer(&renderer, "Renderer", window) do log.panic("Failed to initialize the renderer!")
	defer deinit_renderer(renderer)

	glfw.SetWindowUserPointer(window, &renderer)
	glfw.SetFramebufferSizeCallback(window, glfw_framebuffer_size_callback)
	glfw.SetKeyCallback(window, glfw_key_callback)

	for !glfw.WindowShouldClose(window) {
		glfw.PollEvents()
		if !renderer_render(&renderer) do break
		free_all(context.temp_allocator)
	}
}
