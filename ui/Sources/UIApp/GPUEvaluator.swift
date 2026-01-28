import Foundation
import Metal

final class GPUEvaluator {
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLComputePipelineState

    init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.queue = queue
        let source = Self.shaderSource
        do {
            let library = try device.makeLibrary(source: source, options: nil)
            guard let function = library.makeFunction(name: "evaluate_boards") else { return nil }
            self.pipeline = try device.makeComputePipelineState(function: function)
        } catch {
            return nil
        }
    }

    func evaluate(boards: [Int32], boardCount: Int, iterations: UInt32 = 1) -> [Float] {
        let totalInts = boardCount * 16
        if boards.count < totalInts { return [] }
        guard let commandBuffer = queue.makeCommandBuffer(),
              let commandEncoder = commandBuffer.makeComputeCommandEncoder() else { return [] }

        let inputSize = totalInts * MemoryLayout<Int32>.stride
        let outputSize = boardCount * MemoryLayout<Float>.stride
        guard let inBuffer = device.makeBuffer(bytes: boards, length: inputSize, options: []),
              let outBuffer = device.makeBuffer(length: outputSize, options: []) else { return [] }

        commandEncoder.setComputePipelineState(pipeline)
        commandEncoder.setBuffer(inBuffer, offset: 0, index: 0)
        commandEncoder.setBuffer(outBuffer, offset: 0, index: 1)
        var count = UInt32(boardCount)
        commandEncoder.setBytes(&count, length: MemoryLayout<UInt32>.stride, index: 2)
        var iters = iterations
        commandEncoder.setBytes(&iters, length: MemoryLayout<UInt32>.stride, index: 3)

        let width = max(1, pipeline.threadExecutionWidth)
        let threadsPerThreadgroup = MTLSize(width: width, height: 1, depth: 1)
        let threads = MTLSize(width: boardCount, height: 1, depth: 1)
        commandEncoder.dispatchThreads(threads, threadsPerThreadgroup: threadsPerThreadgroup)
        commandEncoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        let outPtr = outBuffer.contents().bindMemory(to: Float.self, capacity: boardCount)
        return Array(UnsafeBufferPointer(start: outPtr, count: boardCount))
    }

    private static let shaderSource = """
#include <metal_stdlib>
using namespace metal;

kernel void evaluate_boards(const device int *boards [[buffer(0)]],
                            device float *outScores [[buffer(1)]],
                            constant uint &boardCount [[buffer(2)]],
                            constant uint &iterations [[buffer(3)]],
                            uint gid [[thread_position_in_grid]]) {
    if (gid >= boardCount) return;
    uint base = gid * 16u;

    float empty = 0.0;
    float smooth = 0.0;
    float monoRow = 0.0;
    float monoRowRev = 0.0;
    float monoCol = 0.0;
    float monoColRev = 0.0;
    int maxVal = 0;

    // scan board
    for (uint i = 0; i < 16; i++) {
        int v = boards[base + i];
        if (v == 0) empty += 1.0;
        if (v > maxVal) maxVal = v;
    }

    // smoothness + monotonicity (rows)
    for (uint r = 0; r < 4; r++) {
        for (uint c = 0; c < 4; c++) {
            uint idx = r * 4 + c;
            int v = boards[base + idx];
            if (v == 0) continue;
            float logv = log2((float)v);
            if (c + 1 < 4) {
                int nv = boards[base + idx + 1];
                if (nv > 0) {
                    float logn = log2((float)nv);
                    smooth -= fabs(logv - logn);
                }
            }
            if (r + 1 < 4) {
                int nv = boards[base + idx + 4];
                if (nv > 0) {
                    float logn = log2((float)nv);
                    smooth -= fabs(logv - logn);
                }
            }
        }

        for (uint c = 0; c + 1 < 4; c++) {
            int cur = boards[base + r * 4 + c];
            int nxt = boards[base + r * 4 + c + 1];
            float lc = log2((float)(cur + 1));
            float ln = log2((float)(nxt + 1));
            if (cur > nxt) monoRow += lc - ln; else if (nxt > cur) monoRowRev += ln - lc;
        }
    }

    // columns monotonicity
    for (uint c = 0; c < 4; c++) {
        for (uint r = 0; r + 1 < 4; r++) {
            int cur = boards[base + r * 4 + c];
            int nxt = boards[base + (r + 1) * 4 + c];
            float lc = log2((float)(cur + 1));
            float ln = log2((float)(nxt + 1));
            if (cur > nxt) monoCol += lc - ln; else if (nxt > cur) monoColRev += ln - lc;
        }
    }

    float mono = max(monoRow, monoRowRev) + max(monoCol, monoColRev);
    float maxTile = log2((float)(maxVal + 1));

    // corner bonus
    int c0 = boards[base + 0];
    int c1 = boards[base + 3];
    int c2 = boards[base + 12];
    int c3 = boards[base + 15];
    float corner = (maxVal > 0 && (c0 == maxVal || c1 == maxVal || c2 == maxVal || c3 == maxVal)) ? 1.0 : -1.0;

    float score = empty * 130.0 + smooth * 2.5 + mono * 18.0 + maxTile * 22.0 + corner * 45.0;
    float acc = score;
    // heavier compute loop to keep GPU busy
    for (uint i = 0; i < iterations; i++) {
        acc = acc * 1.00001f + 0.0001f;
        acc = acc + sin(acc * 0.0001f);
        acc = acc + cos(acc * 0.0002f);
        acc = acc + sqrt(fabs(acc)) * 0.00001f;
        acc = acc * 0.99999f + 0.00005f;
    }
    outScores[gid] = acc;
}
"""
}
