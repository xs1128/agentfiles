# Experiments and evidence

Read when the report depends on setup, execution, measurement, or analysis. Skip execution when the user wants only a plan or already has enough evidence.

## Valid baseline

Record what can affect the comparison: hardware/architecture, software versions, resource allocations, relevant config, code and dataset identity, connectivity between components. Prove the workload actually runs. An existing image, binary, or open port is not proof.

Probe prerequisites cheaply before large installs or long runs. A cached package may be absent, a listed accelerator may be unusable, internet access does not prove a specific download or peer is reachable.

Validate existing artifacts before reuse and keep originals intact. Do not replace an image or baseline just because a script reruns.

## Define each measurement first

- Subject: process, guest, host, or network path.
- Start/end conditions, units, sampling interval, exclusions.
- Controlled variables, unavoidable differences, workload size, repetitions, warm-up.
- Completion check, expected output, timeout, evidence kept on failure.

Match code, data, resource limits, library versions, seeds, threads, and network conditions where practical, and state remaining mismatches. Pick repetitions by variability, cost, and assignment requirements.

Run a small end-to-end pilot before a batch. CPU use does not mean progress: check readiness, advancing output, or a known result. Use bounded waits. If progress stalls, read the diagnostics instead of extending the timeout.

## Reproducible records

Use a new run folder per run, never overwrite. Keep commands and options, timestamps, config, stdout/stderr, exit status, and raw measurements. For timed comparisons, record workload boundaries and input identity (hashes when they matter).

Separate preparation from measurement so installs and downloads do not distort timings. Reruns must keep prior evidence and not start duplicate services. Clean up only resources the script owns.

Check semantic success, not just exit code. Tools may exit 0 while printing `not supported` or partial counters. Record those as unavailable and keep the diagnostic text.

## Analyze what was measured

Compute summaries from raw records. Keep individual trials and report variability when it changes interpretation. Name the statistic and keep units consistent. A speedup ratio uses the same metric and direction on both sides.

Do not conflate training-loop time with process wall time, process peak RSS with guest memory, or guest memory with hypervisor overhead. Define startup readiness explicitly: prepared startup differs from install, first boot, or resume.

For before/during/after experiments, align clocks and event boundaries and respect sampling resolution: a one-second sample cannot show a millisecond outage. Prove application continuity with the evidence the question requires (unchanged identity, completed work, received bytes, matching outputs).

Name environmental changes that could explain an effect (kernel, background load, run order, network path). Correlation or a plausible mechanism is not proof of one cause. If a required metric cannot be measured, document it and seek an approved alternative. A fallback metric does not automatically satisfy the requirement.
