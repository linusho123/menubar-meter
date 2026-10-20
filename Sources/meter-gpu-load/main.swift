import Foundation
import Metal

// Test harness stand-in: ONE task that keeps the GPU busy about half the time, until it is
// ended, so the meter's GPU column and Activity Monitor's % GPU can be read for a real task.

let source = """
  #include <metal_stdlib>
  using namespace metal;
  kernel void spin(device float *out [[buffer(0)]], uint id [[thread_position_in_grid]]) {
    float x = float(id);
    for (int i = 0; i < 20000; i++) { x = fma(x, 1.000001, 0.5); }
    out[id] = x;
  }
  """

guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
  FileHandle.standardError.write(Data("meter-gpu-load: no GPU\n".utf8))
  exit(1)
}
let library = try device.makeLibrary(source: source, options: nil)
guard let function = library.makeFunction(name: "spin") else { exit(1) }
let pipeline = try device.makeComputePipelineState(function: function)
let threads = 1 << 16
guard let output = device.makeBuffer(length: threads * 4, options: .storageModePrivate) else {
  exit(1)
}

while true {
  guard let buffer = queue.makeCommandBuffer(), let encoder = buffer.makeComputeCommandEncoder()
  else { exit(1) }
  encoder.setComputePipelineState(pipeline)
  encoder.setBuffer(output, offset: 0, index: 0)
  encoder.dispatchThreads(
    MTLSize(width: threads, height: 1, depth: 1),
    threadsPerThreadgroup: MTLSize(width: 256, height: 1, depth: 1))
  encoder.endEncoding()
  buffer.commit()
  buffer.waitUntilCompleted()
  // As long again idle: about half the GPU's time.
  let busy = max(0.001, buffer.gpuEndTime - buffer.gpuStartTime)
  usleep(useconds_t(min(0.2, busy) * 1_000_000))
}
