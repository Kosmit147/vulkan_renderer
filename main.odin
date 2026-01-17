package vulkan_renderer

import "base:runtime"

import "vendor:glfw"

import "core:log"
import "core:mem"

WINDOW_WIDTH :: 1920
WINDOW_HEIGHT :: 1080
WINDOW_TITLE :: "Renderer"

glfw_error_callback :: proc "c" (error_code: i32, description: cstring) {
	context = g_context
	log.errorf("GLFW Error: %v", description)
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
	glfw.WindowHint(glfw.RESIZABLE, glfw.FALSE)

	window := glfw.CreateWindow(WINDOW_WIDTH, WINDOW_HEIGHT, WINDOW_TITLE, nil, nil)
	if window == nil do log.panic("Failed to create a window!")
	defer glfw.DestroyWindow(window)

	for !glfw.WindowShouldClose(window) {
		glfw.PollEvents()
	}
}
