/*
 *  Copyright (c) 2012 The WebRTC project authors. All Rights Reserved.
 *
 *  Use of this source code is governed by a BSD-style license
 *  that can be found in the LICENSE file in the root of the source
 *  tree. An additional intellectual property rights grant can be found
 *  in the file PATENTS.  All contributing project authors may
 *  be found in the AUTHORS file in the root of the source tree.
 */

#include "noise_suppression_x.h"

#include <stdlib.h>

#include "include/real_fft.h"
#include "nsx_core.h"
#include "nsx_defines.h"

NsxHandle *WebRtcNsx_Create() {
    NoiseSuppressionFixedC *self = malloc(sizeof(NoiseSuppressionFixedC));
    self->real_fft = NULL;
    self->initFlag = 0;
    return (NsxHandle *) self;
}

void WebRtcNsx_Free(NsxHandle *nsxInst) {
    WebRtcSpl_FreeRealFFT(((NoiseSuppressionFixedC *) nsxInst)->real_fft);
    free(nsxInst);
}

int WebRtcNsx_Init(NsxHandle *nsxInst, uint32_t fs) {
    return WebRtcNsx_InitCore((NoiseSuppressionFixedC *) nsxInst, fs);
}

int WebRtcNsx_set_policy(NsxHandle *nsxInst, int mode) {
    return WebRtcNsx_set_policy_core((NoiseSuppressionFixedC *) nsxInst, mode);
}

void WebRtcNsx_Process(NsxHandle *nsxInst,
                       const int16_t *const *speechFrame,
                       int num_bands,
                       int16_t *const *outFrame) {
    WebRtcNsx_ProcessCore((NoiseSuppressionFixedC *) nsxInst, speechFrame,
                          num_bands, outFrame);
}

const uint32_t *WebRtcNsx_noise_estimate(const NsxHandle *nsxInst,
                                         int *q_noise) {
    *q_noise = 11;
    const NoiseSuppressionFixedC *self = (const NoiseSuppressionFixedC *) nsxInst;
    if (nsxInst == NULL || self->initFlag == 0) {
        return NULL;
    }
    *q_noise += self->prevQNoise;
    return self->prevNoiseU32;
}

size_t WebRtcNsx_num_freq() {
    return HALF_ANAL_BLOCKL;
}
