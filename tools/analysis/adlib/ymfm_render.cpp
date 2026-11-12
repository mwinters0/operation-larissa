// ymfm_render: OPL2 register log -> 44.1 kHz WAV through ymfm (https://github.com/aaronsgiles/ymfm, BSD-3-Clause):
// ymfm::ym3812 @ 3579545 Hz = 49716 Hz, linear interpolation to 44100 Hz, gain 0.8, mono duplicated to stereo, 16 bit.
// Build: build_ymfm_render.sh (YMFM_DIR = a ymfm checkout).
// usage: ymfm_render <events.txt> <out.wav> <frames>   (the triple may repeat: one chip serves every job, reset() between jobs)
//   events.txt lines: "<opl_sample> <reg hex> <val hex>" (opl_sample = chip-sample time of the write, ascending)
//   env PRERUN=<n>: chip samples generated before a job. ymfm's reset() does not clear the envelope counter, the LFO phase and the
//   noise generator, so a render that must match another one bit for bit starts from the same chip state; what is audible does not depend on it.
#include "ymfm_opl.h"
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <cstring>
#include <vector>
#include <cmath>
struct Ev { uint64_t s; uint8_t r, v; };
static ymfm::ymfm_interface iface; static ymfm::ym3812 chip(iface);   // one chip for every job: reset() between jobs, like the recorder
static int job(const char *evfile, const char *outfile, const char *framesarg) {
    std::vector<Ev> ev; FILE *f = fopen(evfile, "r"); if (!f) return 1;
    unsigned long long s; unsigned r, v;
    char line[256];
    while (fgets(line, sizeof line, f)) if (sscanf(line, "%llu %x %x", &s, &r, &v) == 3) ev.push_back({s, (uint8_t)r, (uint8_t)v});
    fclose(f);
    size_t frames = strtoull(framesarg, 0, 10);
    chip.reset();
    if (const char *pr = getenv("PRERUN")) { unsigned long long k = strtoull(pr, 0, 10); ymfm::ym3812::output_data o0; for (unsigned long long i = 0; i < k; i++) chip.generate(&o0, 1); chip.reset(); }
    uint32_t rate = chip.sample_rate(3579545);
    const double step = (double)rate / 44100.0;
    std::vector<int16_t> pcm; pcm.reserve(frames * 2);
    double outpos = 0; uint64_t ci = 0; int32_t prev = 0, cur = 0; size_t ei = 0;
    while (pcm.size() < frames * 2) {
        while (ei < ev.size() && ev[ei].s <= ci) { chip.write_address(ev[ei].r); chip.write_data(ev[ei].v); ei++; }
        ymfm::ym3812::output_data o; chip.generate(&o, 1);
        prev = cur; cur = o.data[0];
        while (outpos <= (double)ci && pcm.size() < frames * 2) {
            double x = (prev + (cur - prev) * (outpos - ((double)ci - 1.0))) * 0.8;
            if (x > 32767) x = 32767; if (x < -32768) x = -32768;
            pcm.push_back((int16_t)x); pcm.push_back((int16_t)x); outpos += step;
        }
        ci++;
    }
    f = fopen(outfile, "wb");
    uint32_t sr = 44100, br = sr * 4, n = (uint32_t)(frames * 4), riff = 36 + n, fmt = 16; uint16_t pc = 1, ch = 2, ba = 4, bits = 16; uint8_t w[44];
    memcpy(w, "RIFF", 4); memcpy(w + 4, &riff, 4); memcpy(w + 8, "WAVEfmt ", 8); memcpy(w + 16, &fmt, 4);
    memcpy(w + 20, &pc, 2); memcpy(w + 22, &ch, 2); memcpy(w + 24, &sr, 4); memcpy(w + 28, &br, 4);
    memcpy(w + 32, &ba, 2); memcpy(w + 34, &bits, 2); memcpy(w + 36, "data", 4); memcpy(w + 40, &n, 4);
    fwrite(w, 1, 44, f); fwrite(pcm.data(), 4, frames, f); fclose(f);
    return 0;
}

int main(int argc, char **argv) {
    if (argc < 4 || (argc - 1) % 3) { fprintf(stderr, "usage: %s (events.txt out.wav frames)+\n", argv[0]); return 2; }
    for (int i = 1; i < argc; i += 3) if (job(argv[i], argv[i + 1], argv[i + 2])) return 1;
    return 0;
}
