# Personal English Learning

A single-learner system that measures the Learner's English vocabulary at regular intervals and publishes it, so external agents can recommend suitable reading and video. It is the broad-range vocabulary data provider among three tools: daily word study happens in 墨墨背单词, and recommending content is the Recommendation Agent's job; both are outside this system.

## Language

**Learner**:
The single person this system serves and models.
_Avoid_: User, student, account

**Observation**:
A single immutable record of the Learner's response to one word, from a Vocabulary Test. Observations are only ever appended, never changed.
_Avoid_: Event, log entry, answer

**Learner Profile**:
The system's current picture of the Learner's vocabulary, always recomputed from Observations: every word's Word Band and probability of being known, the estimated vocabulary size, and what is needed to compute Coverage.
_Avoid_: Progress, level, stats

**Word Band**:
One of three classifications of a word relative to the Learner: Mastered, Target, or Distant.
_Avoid_: Difficulty, tier, grade

**Mastered**:
A Word Band for words the Learner already knows reliably.
_Avoid_: Easy, known, 太简单

**Target**:
A Word Band for words at the edge of the Learner's knowledge: not yet reliably known, but close enough to be picked up from context or study.
_Avoid_: Learning, 正好该学

**Distant**:
A Word Band for words currently far beyond the Learner's knowledge.
_Avoid_: Hard, advanced, 太遥远

**Coverage**:
The share of the words in a given text that the Learner already knows. Comprehensible input means Coverage high enough to read without translation.
_Avoid_: Readability, difficulty score

**Vocabulary Test**:
A sampled assessment that estimates the Learner's total vocabulary and its Word Band distribution, and surfaces specific unknown words.
_Avoid_: Quiz, exam

**Baseline Test**:
The one-time full-length Vocabulary Test taken at the start, which later short tests refine.
_Avoid_: Placement test, initial test

**Recommendation Agent**:
The external AI agent that reads this system's published vocabulary data and the Learner's 墨墨背单词 study data every day, reconciles them itself, and recommends reading and video at a suitable level. Outside this system.
_Avoid_: Bot, recommender

**Progress Report**:
A concise snapshot of the Learner Profile published as a GitHub issue for external agents to read. A new one supersedes the previous one after each day's first Vocabulary Test; only the newest is current. It describes the Learner's level, never their content preferences.
_Avoid_: Status update, log, summary
