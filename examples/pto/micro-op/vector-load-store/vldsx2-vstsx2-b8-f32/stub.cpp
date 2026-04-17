// -----------------------------------------------------------------------------
// case: micro-op/vector-load-store/vldsx2-vstsx2-b8-f32
// family: vector-load-store
// target_ops: pto.vldsx2, pto.vstsx2
// scenarios: core-f32, full-mask, paired-roundtrip, dintlv-b8-intlv-b8, width-agnostic-dist
// -----------------------------------------------------------------------------

#ifndef __global__
#define __global__
#endif

#ifndef __gm__
#define __gm__
#endif

extern "C" __global__ [aicore] void vldx2_vstsx2_b8_f32_kernel(__gm__ float *v1,
                                                               __gm__ float *v2) {
  (void)v1;
  (void)v2;
}
