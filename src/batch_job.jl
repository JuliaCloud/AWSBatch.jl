import AWSSDK.Batch: describe_jobs, submit_job
import AWSSDK.CloudWatchLogs: get_log_events


"""
    BatchJob

Stores a batch job id in order to:

- `describe` a job and its parameters
- check on the `status` of a job
- `wait` for a job to complete
- fetch `log_events`

# Fields
- `id::AbstractString`: jobId
"""
struct BatchJob
    id::AbstractString
end

"""
    submit(
        name::AbstractString,
        definition::JobDefinition,
        queue::AbstractString;
        container::AbstractDict=Dict(),
        region::AbstractString="",
    ) -> BatchJob

Handles submitting the batch job. Returns a `BatchJob` wrapper for the id.
"""
function submit(
    name::AbstractString,
    definition::JobDefinition,
    queue::AbstractString;
    container::AbstractDict=Dict(),
    region::AbstractString="",
)
    region = isempty(region) ? "us-east-1" : region
    config = AWSConfig(:creds => AWSCredentials(), :region => region)

    debug(logger, "Submitting job $name")
    input = [
        "jobName" => name,
        "jobDefinition" => definition.name,
        "jobQueue" => queue,
        "containerOverrides" => container,
    ]
    debug(logger, "Input: $input")

    response = @mock submit_job(config, input)
    job = BatchJob(response["jobId"])

    info(logger, "Submitted job $(name)::$(job.id).")

    return job
end

"""
    describe(job::BatchJob) -> Dict

Provides details about the AWS batch job.
"""
function describe(job::BatchJob)
    response = @mock describe_jobs(; jobs=[job.id])
    isempty(response["jobs"]) && error(logger, "Job $(job.id) not found.")
    debug(logger, "Job $(job.id): $response")
    return first(response["jobs"])
end

"""
    JobDefinition

Returns the job definition corresponding to a batch job.
"""
JobDefinition(job::BatchJob) = JobDefinition(describe(job)["jobDefinition"])

"""
    status(job::BatchJob) -> JobState

Returns the current status of a job.
"""
function status(job::BatchJob)::JobState
    details = describe(job)
    return parse(JobState, details["status"])
end

"""
    wait(
        cond::Function,
        job::BatchJob;
        timeout=600,
        delay=5
    )

Polls the batch job state until it hits one of the conditions in `cond`.
The loop will exit if it hits a `failure` condition and will not catch any excpetions.
The polling interval can be controlled with `delay` and `timeout` provides a maximum
polling time.

# Examples
```julia
julia> wait(state -> state < SUCCEEDED, job)
true
```
"""
function Base.wait(
    cond::Function,
    job::BatchJob;
    timeout=600,
    delay=5
)
    completed = false
    last_state = PENDING
    initial = true

    start_time = time()  # System time in seconds since epoch
    while time() - start_time < timeout
        state = status(job)

        if state != last_state || initial
            info(logger, "$(job.id) status $state")

            if !cond(state)
                completed = true
                break
            end

            last_state = state
        end

        initial && (initial = false)
        sleep(delay)
    end

    if !completed
        message = "Waiting on job $(job.id) timed out."

        if !initial
            message *= " Last known state $last_state."
        end

        error(logger, message)
    end

    return completed
end

"""
    wait(
        job::BatchJob,
        cond::Vector{JobState}=[RUNNING, SUCCEEDED],
        failure::Vector{JobState}=[FAILED];
        kwargs...,
    )

Polls the batch job state until it hits one of the conditions in `cond`.
The loop will exit if it hits a `failure` condition and will not catch any excpetions.
The polling interval can be controlled with `delay` and `timeout` provides a maximum
polling time.
"""
function Base.wait(
    job::BatchJob,
    cond::Vector{JobState}=[RUNNING, SUCCEEDED],
    failure::Vector{JobState}=[FAILED];
    kwargs...,
)
    wait(job; kwargs...) do state
        if state in cond
            false
        elseif state in failure
            error(logger, "Job $(job.id) hit failure condition $state.")
            false
        else
            true
        end
    end
end

"""
    log_events(job::BatchJob) -> Vector{LogEvent}

Fetches the logStreamName, fetches the CloudWatch logs and returns a vector of messages.

NOTES:
- The `logStreamName` isn't available until the job is RUNNING, so you may want to use
  `wait(job)` or `wait(job, [AWSBatch.SUCCEEDED])` prior to calling this function.
- We do not support pagination, so this function is limited to 10,000 log messages by
  default.
"""
function log_events(job::BatchJob)
    container_details = describe(job)["container"]

    if "logStreamName" in keys(container_details)
        stream = container_details["logStreamName"]

        info(logger, "Fetching log events from $stream")
        output = get_log_events(logGroupName="/aws/batch/job", logStreamName=stream)
        return convert.(LogEvent, output["events"])
    else
        info(logger, "No log events found for job $(job.id).")
        return LogEvent[]
    end
end
