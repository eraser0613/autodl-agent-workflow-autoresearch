**AUTORESEARCH Generic Template**

This file is not a hard-coded rulebook for one specific repository. It is a generic template for telling `Codex / Claude Code / Code Agent` how to run continuous research inside your own main project.

It is useful when the agent is not only responsible for connecting to AutoDL and starting training, but also responsible for:

- reading historical results
- proposing new ideas
- deciding whether to continue or stop
- cleaning remote artifacts

This template is intentionally not tied to:

- a specific model
- a specific paper direction
- a specific dataset
- a specific metric threshold
- a specific channel type

You should copy it into your own main repository and rewrite it into a project-specific research policy.

**What This Kind Of File Should Solve**

A good AutoResearch policy should tell the agent at least the following:

- what the overall research goal is
- which metric is the top priority
- which conditions are hard constraints
- which system assumptions must not change
- how long each round should run by default
- when early stopping is allowed
- when continuation is allowed
- when a scheme must be rejected
- when failed artifacts must be deleted
- how duplicate schemes are avoided
- what fields must appear in each round report
- whether a fixed communication language is required

**Recommended Sections**

In your own main project, the research policy should clearly define at least the following areas.

`Mission`

- What is the primary objective
- What is the secondary objective
- How are those objectives ordered

For example:

- First satisfy a quality floor
- Then minimize bitrate, latency, memory use, parameter count, or training cost

`Evaluation Metrics`

- Which validation metrics matter most
- How the metrics are ranked
- Which metric is a hard threshold
- Which metric is the optimization direction

`Hard Constraints`

- Which system settings must not change
- Which assumptions must remain aligned with the current project
- Which resource limits must be respected

For example:

- Do not change the base task definition
- Do not break the core input-output protocol
- Do not keep useless remote artifacts indefinitely

`Scheme Requirements`

- Whether every round must propose a new scheme
- What counts as a genuinely new scheme
- Whether hyperparameter-only changes are allowed
- Whether bold architecture jumps are allowed
- Whether major new directions may create separate training scripts

It is usually a good idea to state explicitly:

- Hyperparameter-only changes do not count as a new scheme by default
- If a family is revisited, the agent must explain the essential difference from the nearest historical scheme

`Training Rhythm`

- How many epochs, steps, or how much time a new scheme should run by default
- When an intermediate review must happen
- Whether obviously failing runs may stop early
- Under what conditions the next stage is allowed

`Mid-Round Decision Rules`

At an intermediate checkpoint, the policy should usually require the agent to analyze:

- the current primary metric
- the current cost metric
- recent trends over several epochs or steps
- whether structural failure is happening
- whether there is still credible room for improvement
- whether the run is worth continuing

`Early Stop Conditions`

It is usually reasonable to explicitly allow early stopping when:

- there is already high-confidence evidence of failure
- the trend clearly shows the target region is unlikely to be reached
- the run is collapsing, stalling, or structurally broken
- the idea adds no real value over historical schemes

The policy should also require the agent to explain:

- why the run was stopped early
- what evidence supports that decision
- why further resource use is not justified

`Continuation Conditions`

The agent should continue only when conditions like these are satisfied:

- the metrics are still improving
- the run has not clearly saturated
- no structural failure is present
- the direction still shows clear potential relative to historical schemes

`Final Verdict Rules`

When a scheme reaches its final checkpoint, the agent should be forced to issue a decision such as:

- keep as a candidate
- keep under observation
- reject as failed

Do not allow the agent to merely relay logs without a decision.

`Failed Scheme Cleanup Rules`

The policy should define:

- whether failed checkpoints must be deleted on the remote server
- whether the matching log directory must also be deleted
- what summary must be preserved before deletion
- how many historical runs may remain on the remote server at the same time

`Historical Scheme Tracking And Deduplication`

If you do not want the agent to repeat the same ideas, the policy should require:

- every new scheme must be compared against historical schemes before it is started
- the agent must identify the nearest similar scheme
- the agent must explain the essential difference
- name-only changes or tiny hyperparameter changes should count as duplicates by default
- if an old failed direction is revisited, the agent must justify what decisive new factor has changed

`Per-Round Output Format`

A good policy usually requires each round to report at least:

- scheme name
- what changed
- core hypothesis
- difference from the nearest historical scheme
- why it could theoretically be better
- training command
- intermediate checkpoint result
- final verdict
- whether remote artifacts were deleted
- what the next direction should be

`Language Requirement`

If you want the agent to always communicate in a fixed language, write that rule into the policy.

For example:

- all reports must be written in Chinese
- all experiment conclusions must be written in English

Do not rely only on chat history for this; put it in the policy file.

**Recommended Usage**

You can copy this template into your own main repository and name it something like:

```text
AUTORESEARCH.md
```

Then, when starting a research campaign with your coding agent, tell it something like:

```text
From now on, all continuous research in this project must follow AUTORESEARCH.md.
First analyze historical results, then propose a new idea, then edit code locally, sync to AutoDL, launch training, analyze the outcome, and decide whether to continue or stop.
```

**How This Relates To This Toolkit**

This toolkit is responsible for:

- SSH connection
- code sync
- remote training launch
- log inspection
- TensorBoard tunnel setup

Your main project research policy is responsible for:

- what to research
- why to research it
- when to continue
- when to stop
- what counts as failure
- what counts as a duplicate scheme

Keeping the connection tools separate from the research rules makes the whole setup much easier to reuse across projects, tasks, models, and servers.
