/*
Copyright 2020 The OneFlow Authors. All rights reserved.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/
#include "oneflow/core/framework/framework.h"
#include "oneflow/user/kernels/gather_dim_kernel_util.h"
#include "oneflow/user/kernels/gather_dim_kernels.h"

namespace oneflow {

namespace user_op {

template<typename IN_T, typename IDX_T>
__global__ void DoCUDAGatherDim(CoordinateOffsetConverter<IDX_T> input_helper,
                                CoordinateOffsetConverter<IDX_T> index_helper, int64_t elem_cnt,
                                int64_t dim, const IDX_T* index, const IN_T* input, IN_T* output) {
  DoGatherDim<IN_T, IDX_T>(input_helper, index_helper, elem_cnt, dim, index, input, output);
}

template<typename IDX_T, typename IN_T>
struct GatherDimFunctor<DeviceType::kGPU, IN_T, IDX_T> final {
  void operator()(CoordinateOffsetConverter<IDX_T> input_nd_helper,
                  CoordinateOffsetConverter<IDX_T> index_nd_helper, int64_t elem_cnt, int64_t dim,
                  const IDX_T* index, const IN_T* input, IN_T* output, DeviceCtx* ctx) {
    RUN_CUDA_KERNEL((DoCUDAGatherDim<IN_T, IDX_T>), ctx, BlocksNum4ThreadsNum(elem_cnt),
                    input_nd_helper, index_nd_helper, elem_cnt, dim, index, input, output);
  }
};

template<typename IN_T, typename IDX_T>
__global__ void DoCUDAScatterDimAdd(CoordinateOffsetConverter<IDX_T> src_helper,
                                    CoordinateOffsetConverter<IDX_T> output_helper,
                                    int64_t elem_cnt, int64_t dim, const IDX_T* index,
                                    const IN_T* src, IN_T* output) {
  DoScatterDimAdd<IN_T, IDX_T>(src_helper, output_helper, elem_cnt, dim, index, src, output);
}

template<typename IN_T, typename IDX_T>
struct ScatterDimAddFunctor<DeviceType::kGPU, IN_T, IDX_T> final {
  void operator()(CoordinateOffsetConverter<IDX_T> src_nd_helper,
                  CoordinateOffsetConverter<IDX_T> output_nd_helper, int64_t elem_cnt, int64_t dim,
                  const IDX_T* index, const IN_T* src, IN_T* output, DeviceCtx* ctx) {
    RUN_CUDA_KERNEL((DoCUDAScatterDimAdd<IN_T, IDX_T>), ctx, BlocksNum4ThreadsNum(elem_cnt),
                    src_nd_helper, output_nd_helper, elem_cnt, dim, index, src, output);
  }
};

// float16 special case of ScatterDimAddFunctor template
template<typename IDX_T>
struct ScatterDimAddFunctor<DeviceType::kGPU, float16, IDX_T> final {
  void operator()(CoordinateOffsetConverter<IDX_T> src_nd_helper,
                  CoordinateOffsetConverter<IDX_T> output_nd_helper, int64_t elem_cnt, int64_t dim,
                  const IDX_T* index, const float16* src, float16* output, DeviceCtx* ctx) {
    RUN_CUDA_KERNEL((DoCUDAScatterDimAdd<half, IDX_T>), ctx, BlocksNum4ThreadsNum(elem_cnt),
                    src_nd_helper, output_nd_helper, elem_cnt, dim, index,
                    reinterpret_cast<const half*>(src), reinterpret_cast<half*>(output));
  }
};

#define REGISTER_GATHERDIM_GPUKERNEL(device, in_type, indices_type)                             \
  REGISTER_USER_KERNEL("gather_dim")                                                            \
      .SetCreateFn<                                                                             \
          GatherDimKernel<device, OF_PP_PAIR_FIRST(in_type), OF_PP_PAIR_FIRST(indices_type)>>() \
      .SetIsMatchedHob((user_op::HobDeviceTag() == device)                                      \
                       & (user_op::HobDataType("input", 0) == OF_PP_PAIR_SECOND(in_type))       \
                       & (user_op::HobDataType("index", 0) == OF_PP_PAIR_SECOND(indices_type)));

#define REGISTER_SCATTERDIMADD_GPUKERNEL(device, in_type, indices_type)                          \
  REGISTER_USER_KERNEL("scatter_dim_add_like")                                                   \
      .SetCreateFn<                                                                              \
          ScatterDimKernel<device, OF_PP_PAIR_FIRST(in_type), OF_PP_PAIR_FIRST(indices_type)>>() \
      .SetIsMatchedHob((user_op::HobDeviceTag() == device)                                       \
                       & (user_op::HobDataType("src", 0) == OF_PP_PAIR_SECOND(in_type))          \
                       & (user_op::HobDataType("index", 0) == OF_PP_PAIR_SECOND(indices_type)));

#define GATHER_DATA_TYPE_SEQ ARITHMETIC_DATA_TYPE_SEQ FLOAT16_DATA_TYPE_SEQ

OF_PP_SEQ_PRODUCT_FOR_EACH_TUPLE(REGISTER_GATHERDIM_GPUKERNEL, (DeviceType::kGPU),
                                 GATHER_DATA_TYPE_SEQ, INDEX_DATA_TYPE_SEQ)

OF_PP_SEQ_PRODUCT_FOR_EACH_TUPLE(REGISTER_SCATTERDIMADD_GPUKERNEL, (DeviceType::kGPU),
                                 GATHER_DATA_TYPE_SEQ, INDEX_DATA_TYPE_SEQ)

}  // namespace user_op
}  // namespace oneflow