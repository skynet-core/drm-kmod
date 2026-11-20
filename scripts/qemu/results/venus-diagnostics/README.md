# Vulkan diagnostics

The first NVIDIA Venus runs passed Vulkan enumeration, mapped-buffer
readback and the present API checks. The captures exposed horizontal
stride corruption in the rendered image. The two images below show the
same RTX 3090, KMSAN, virtio-vga-gl and Plasma Wayland setup before and
after installing the Mesa NVIDIA PRIME pitch fix. The first image is
excluded from the final pass record.

- [Before the fix](nvidia-before-pitch-fix.png)
- [After the fix](nvidia-after-pitch-fix.png)

The display in the follow-up image captured a newly launched 500-pixel
cube with the repaired ICD. The terminal retains the earlier numerical
test output. The final matrix runs both workloads again with the repaired
ICD for every case. See the [NVIDIA EGL import report](https://forums.developer.nvidia.com/t/egl-import-via-egl-ext-image-dma-buf-import-modifiers-ignores-explicit-stride-causes-image-distortion-in-virtio-gpu-venus/364360).

An earlier KASAN run also recorded a stock FreeBSD device pager and
allocator WITNESS lock-order warning during mapping teardown. The
[WITNESS stack](witness-badstacks.log) and [kernel log](witness-dmesg.log)
preserve that report.
