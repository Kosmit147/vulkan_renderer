package vulkan_renderer

import vk "vendor:vulkan"

create_buffer :: proc(device: vk.Device,
		      physical_device: vk.PhysicalDevice,
		      size: vk.DeviceSize,
		      usage: vk.BufferUsageFlags,
		      properties: vk.MemoryPropertyFlags) -> (buffer: vk.Buffer,
							      buffer_memory: vk.DeviceMemory,
							      ok := false) {
	buffer_create_info := vk.BufferCreateInfo{
		sType = .BUFFER_CREATE_INFO,
		size = size,
		usage = usage,
		sharingMode = .EXCLUSIVE,
	}

	if vk.CreateBuffer(device, &buffer_create_info, nil, &buffer) != .SUCCESS do return
	defer if !ok do vk.DestroyBuffer(device, buffer, nil)

	buffer_memory_requirements: vk.MemoryRequirements
	vk.GetBufferMemoryRequirements(device, buffer, &buffer_memory_requirements)

	memory_allocate_info := vk.MemoryAllocateInfo{
		sType = .MEMORY_ALLOCATE_INFO,
		allocationSize = buffer_memory_requirements.size,
		memoryTypeIndex = find_memory_type(physical_device,
						   buffer_memory_requirements.memoryTypeBits,
						   properties) or_return,
	}

	if vk.AllocateMemory(device, &memory_allocate_info, nil, &buffer_memory) != .SUCCESS do return
	defer if !ok do vk.FreeMemory(device, buffer_memory, nil)

	if vk.BindBufferMemory(device, buffer, buffer_memory, 0) != .SUCCESS do return

	ok = true
	return
}

destroy_buffer :: proc(device: vk.Device, buffer: vk.Buffer, buffer_memory: vk.DeviceMemory) {
	vk.DestroyBuffer(device, buffer, nil)
	vk.FreeMemory(device, buffer_memory, nil)
}

copy_buffer :: proc(device: vk.Device,
		    command_pool: vk.CommandPool,
		    queue: vk.Queue,
		    src_buffer, dst_buffer: vk.Buffer,
		    size: vk.DeviceSize) -> (ok := false) {
	command_buffer := begin_single_time_commands(device, command_pool) or_return
	copy_region := vk.BufferCopy {
		size = cast(vk.DeviceSize)size
	}
	vk.CmdCopyBuffer(command_buffer, src_buffer, dst_buffer, 1, &copy_region)
	submit_single_time_commands(command_buffer, queue, device, command_pool)

	ok = true
	return
}

find_memory_type :: proc(device: vk.PhysicalDevice, type_bits: u32, properties: vk.MemoryPropertyFlags) -> (u32, bool) {
	memory_properties: vk.PhysicalDeviceMemoryProperties
	vk.GetPhysicalDeviceMemoryProperties(device, &memory_properties)
	memory_types := memory_properties.memoryTypes[:memory_properties.memoryTypeCount]

	for memory_type, i in memory_types {
		if type_bits & (1 << u32(i)) != 0 && (properties <= memory_type.propertyFlags) {
			return u32(i), true
		}
	}

	return max(u32), false
}
