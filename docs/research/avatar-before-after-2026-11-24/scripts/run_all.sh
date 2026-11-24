S=/tmp/claude-0/-home-user/e4099752-5f8a-5b57-9c7d-84efe288e985/scratchpad
for n in ava-en ava-es ethan-en ethan-es sofia-en sofia-es diego-en diego-es; do
  (cd /home/user/wt-before && QA_JOBS=$S/ondevice-qa/jobs QA_OUT=$S/before-after/work/before QA_K=1.0 QA_ONLY=$n /root/fl/flutter/bin/flutter test --concurrency=2 test/zz_sim_ba_test.dart >$S/before-after/work/before-$n.log 2>&1) &
  (cd /home/user/wt-after && QA_JOBS=$S/ondevice-qa/jobs QA_OUT=$S/before-after/work/after QA_K=1.2 QA_ONLY=$n /root/fl/flutter/bin/flutter test --concurrency=2 test/zz_sim_ba_test.dart >$S/before-after/work/after-$n.log 2>&1) &
  wait
  python3 $S/before-after/scripts/encode_ba.py $n && rm -rf $S/before-after/work/before/$n $S/before-after/work/after/$n
done
echo DONE
