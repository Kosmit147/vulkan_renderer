package vulkan_renderer

import vk "vendor:vulkan"

begin_single_time_commands :: proc(device: vk.Device,
				   command_pool: vk.CommandPool) -> (command_buffer: vk.CommandBuffer,
								     ok := false) #optional_ok {
	command_buffer_allocate_info := vk.CommandBufferAllocateInfo {
		sType = .COMMAND_BUFFER_ALLOCATE_INFO,
		level = .PRIMARY,
		commandPool = command_pool,
		commandBufferCount = 1,
	}

	if vk.AllocateCommandBuffers(device, &command_buffer_allocate_info, &command_buffer) != .SUCCESS do return

	command_buffer_begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = { .ONE_TIME_SUBMIT },
	}

	vk.BeginCommandBuffer(command_buffer, &command_buffer_begin_info)

	ok = true
	return
}

submit_single_time_commands :: proc(command_buffer: vk.CommandBuffer,
				    queue: vk.Queue,
				    device: vk.Device,
				    command_pool: vk.CommandPool) {
	command_buffer := command_buffer
	vk.EndCommandBuffer(command_buffer)

	submit_info := vk.SubmitInfo {
		sType = .SUBMIT_INFO,
		commandBufferCount = 1,
		pCommandBuffers = &command_buffer,
	}

	vk.QueueSubmit(queue, 1, &submit_info, vk.Fence(0))
	vk.QueueWaitIdle(queue)
	vk.FreeCommandBuffers(device, command_pool, 1, &command_buffer)
}
