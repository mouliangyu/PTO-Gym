#ifndef __global__
#define __global__
#endif

#ifndef __gm__
#define __gm__
#endif

extern "C" __global__ [aicore] void vcvt_f32_to_f16_pk_b32_kernel(__gm__ float *v1,
                                                                  __gm__ half *v2) {
  (void)v1;
  (void)v2;
}
