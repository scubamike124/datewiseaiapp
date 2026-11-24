# Kokoro-82M samples (rendered 2026-11-24, CPU, free)
Same English and Spanish test text per voice. These are NOT what customers hear (they hear Apple voices) and Kokoro is not recommended for Spanish.
- Ava: kokoro_ava_af_heart_s1.0.wav (A-grade voice), s0.9 = slower; kokoro_ava_alt_af_bella_s1.0.wav
- Ethan: kokoro_ethan_am_michael_s1.0.wav, kokoro_ethan_alt_am_puck_s1.0.wav
- Sofia (ES): kokoro_sofia_ef_dora_s1.0.wav, s0.9 slower. Diego (ES): kokoro_diego_em_alex_s1.0.wav, kokoro_diego_alt_em_santa_s1.0.wav
- Accent: Kokoro documents no Mexican accent for ef_dora, em_alex, em_santa. Do not assume it. Native Mexican listener needed.
- Timing: kokoro_bench.json (wall time under heavy host load, load avg 13 on 4 cores: unreliable), kokoro_cpu_time.json (1 thread, CPU seconds per audio second about 0.73).
Spanish text: "Qué bueno que me preguntas. Una primera cita no tiene que ser perfecta. Elige un lugar tranquilo, haz una pregunta de verdad y deja que haya silencio. Tú puedes con esto." (neutral wording, no Mexican markers).
