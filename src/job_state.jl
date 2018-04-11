# https://docs.aws.amazon.com/batch/latest/userguide/job_states.html
@doc """
    BatchStatus

An enum for representing different possible AWS Batch job states.

See [docs](http://docs.aws.amazon.com/batch/latest/userguide/job_states.html) for details.
""" JobState

@enum JobState SUBMITTED PENDING RUNNABLE STARTING RUNNING SUCCEEDED FAILED

const STATE_MAP = Dict(string(s) => s for s in instances(JobState))
Base.parse(::Type{JobState}, str::AbstractString) = STATE_MAP[str]
