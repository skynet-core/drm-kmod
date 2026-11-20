/* SPDX-License-Identifier: BSD-2-Clause */
#include <stdio.h>
#include <stdlib.h>
#include <vulkan/vulkan.h>

static void
require(int ok, const char *operation)
{
	if (!ok) {
		fprintf(stderr, "FAIL: %s\n", operation);
		exit(1);
	}
}

#define VK_CHECK(call) require((call) == VK_SUCCESS, #call)

int
main(void)
{
	const VkApplicationInfo app = {
		.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO,
		.apiVersion = VK_API_VERSION_1_2,
	};
	const VkInstanceCreateInfo instance_info = {
		.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
		.pApplicationInfo = &app,
	};
	VkInstance instance;
	VkPhysicalDevice gpu;
	uint32_t count = 1;

	VK_CHECK(vkCreateInstance(&instance_info, NULL, &instance));
	VK_CHECK(vkEnumeratePhysicalDevices(instance, &count, &gpu));
	require(count == 1, "one selected Vulkan device");

	VkPhysicalDeviceDriverProperties driver = {
		.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DRIVER_PROPERTIES,
	};
	VkPhysicalDeviceProperties2 properties = {
		.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2,
		.pNext = &driver,
	};
	vkGetPhysicalDeviceProperties2(gpu, &properties);
	require(driver.driverID == VK_DRIVER_ID_MESA_VENUS &&
	    (properties.properties.deviceType == VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU ||
	     properties.properties.deviceType == VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU),
	    "hardware Venus device");

	vkGetPhysicalDeviceQueueFamilyProperties(gpu, &count, NULL);
	VkQueueFamilyProperties *families = calloc(count, sizeof(*families));
	require(families != NULL, "allocate queue family properties");
	vkGetPhysicalDeviceQueueFamilyProperties(gpu, &count, families);
	uint32_t family = 0;
	while (family < count && !(families[family].queueFlags & VK_QUEUE_GRAPHICS_BIT))
		family++;
	require(family < count, "graphics queue");
	free(families);

	const float priority = 1.0f;
	const VkDeviceQueueCreateInfo queue_info = {
		.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
		.queueFamilyIndex = family, .queueCount = 1, .pQueuePriorities = &priority,
	};
	const VkDeviceCreateInfo device_info = {
		.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
		.queueCreateInfoCount = 1, .pQueueCreateInfos = &queue_info,
	};
	VkDevice device;
	VkQueue queue;
	VK_CHECK(vkCreateDevice(gpu, &device_info, NULL, &device));
	vkGetDeviceQueue(device, family, 0, &queue);

	const VkBufferCreateInfo buffer_info = {
		.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
		.size = 4096, .usage = VK_BUFFER_USAGE_TRANSFER_DST_BIT,
	};
	VkBuffer buffer;
	VkMemoryRequirements requirements;
	VkPhysicalDeviceMemoryProperties memory_properties;
	VK_CHECK(vkCreateBuffer(device, &buffer_info, NULL, &buffer));
	vkGetBufferMemoryRequirements(device, buffer, &requirements);
	vkGetPhysicalDeviceMemoryProperties(gpu, &memory_properties);
	const VkMemoryPropertyFlags coherent = VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT |
	    VK_MEMORY_PROPERTY_HOST_COHERENT_BIT;
	uint32_t type = 0;
	while (type < memory_properties.memoryTypeCount &&
	    (!(requirements.memoryTypeBits & (1U << type)) ||
	     (memory_properties.memoryTypes[type].propertyFlags & coherent) != coherent))
		type++;
	require(type < memory_properties.memoryTypeCount, "coherent mappable memory");

	const VkMemoryAllocateInfo allocate = {
		.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
		.allocationSize = requirements.size, .memoryTypeIndex = type,
	};
	VkDeviceMemory memory;
	void *mapped;
	VK_CHECK(vkAllocateMemory(device, &allocate, NULL, &memory));
	VK_CHECK(vkBindBufferMemory(device, buffer, memory, 0));
	VK_CHECK(vkMapMemory(device, memory, 0, VK_WHOLE_SIZE, 0, &mapped));

	const VkCommandPoolCreateInfo pool_info = {
		.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO, .queueFamilyIndex = family,
	};
	VkCommandPool pool;
	VkCommandBuffer commands[2];
	VK_CHECK(vkCreateCommandPool(device, &pool_info, NULL, &pool));
	const VkCommandBufferAllocateInfo command_info = {
		.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
		.commandPool = pool, .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY,
		.commandBufferCount = 2,
	};
	VK_CHECK(vkAllocateCommandBuffers(device, &command_info, commands));
	const uint32_t pattern[] = { 0x12345678, 0xfedcba98 };
	const VkCommandBufferBeginInfo begin = {
		.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
	};
	const VkMemoryBarrier barrier = {
		.sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER,
		.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT,
		.dstAccessMask = VK_ACCESS_HOST_READ_BIT,
	};
	for (unsigned i = 0; i < 2; i++) {
		VK_CHECK(vkBeginCommandBuffer(commands[i], &begin));
		vkCmdFillBuffer(commands[i], buffer, 0, buffer_info.size, pattern[i]);
		vkCmdPipelineBarrier(commands[i], VK_PIPELINE_STAGE_TRANSFER_BIT,
		    VK_PIPELINE_STAGE_HOST_BIT, 0, 1, &barrier, 0, NULL, 0, NULL);
		VK_CHECK(vkEndCommandBuffer(commands[i]));
	}

	const uint32_t *words = mapped;
	for (unsigned i = 0; i < 120; i++) {
		const VkSubmitInfo submit = {
			.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO,
			.commandBufferCount = 1, .pCommandBuffers = &commands[i % 2],
		};
		VK_CHECK(vkQueueSubmit(queue, 1, &submit, VK_NULL_HANDLE));
		VK_CHECK(vkQueueWaitIdle(queue));
		for (size_t j = 0; j < buffer_info.size / sizeof(*words); j++) {
			if (words[j] != pattern[i % 2]) {
				fprintf(stderr, "FAIL: Vulkan write %u word %zu: %#x expected %#x\n",
				    i, j, words[j], pattern[i % 2]);
				return 1;
			}
		}
	}
	puts("PASS: 120 Vulkan GPU writes with full readback");
	vkDestroyCommandPool(device, pool, NULL);
	vkUnmapMemory(device, memory);
	vkDestroyBuffer(device, buffer, NULL);
	vkFreeMemory(device, memory, NULL);
	vkDestroyDevice(device, NULL);
	vkDestroyInstance(instance, NULL);
	return 0;
}
