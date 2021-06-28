
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
@auto_hash_equals struct BatchJob
    id::AbstractString
end

"""
    submit(
        name::AbstractString,
        definition::JobDefinition,
        queue::AbstractString;
        container::AbstractDict=Dict(),
        parameters::Dict{String,String}=Dict{String, String}(),
        region::AbstractString="",
        num_jobs::Integer=1,
    ) -> BatchJob

Handles submitting the batch job. Returns a `BatchJob` wrapper for the id.
"""
function submit(
    name::AbstractString,
    definition::JobDefinition,
    queue::AbstractString;
    container::AbstractDict=Dict(),
    parameters::Dict{String,String}=Dict{String, String}(),
    num_jobs::Integer=1,
    aws_config::AbstractAWSConfig=global_aws_config(),
)
    debug(logger, "Submitting job \"$name\"")
    input = OrderedDict(
        "parameters" => parameters,
        "containerOverrides" => container,
    )

    if num_jobs > 1
        # https://docs.aws.amazon.com/batch/latest/userguide/array_jobs.html
        @assert 2 <= num_jobs <= 10_000
        push!(input, "arrayProperties" => ["size" => num_jobs])
    end

    debug(logger, "Input: $input")

    response = @mock Batch.submit_job(definition.arn, name, queue, input; aws_config=aws_config)
    job = BatchJob(response["jobId"])

    if num_jobs > 1
        info(logger, "Submitted array job \"$(name)\" ($(job.id), n=$(num_jobs))")
    else
        info(logger, "Submitted job \"$(name)\" ($(job.id))")
    end

    return job
end

"""
    describe(job::BatchJob) -> Dict

Provides details about the AWS batch job.
"""
function describe(job::BatchJob; aws_config::AbstractAWSConfig=global_aws_config())
    response = @mock Batch.describe_jobs([job.id]; aws_config=aws_config)
    isempty(response["jobs"]) && error(logger, "Job $(job.id) not found.")
    debug(logger, "Job $(job.id): $response")
    return first(response["jobs"])
end

"""
    JobDefinition

Returns the job definition corresponding to a batch job.
"""
function JobDefinition(job::BatchJob; aws_config::AbstractAWSConfig=global_aws_config())
    JobDefinition(describe(job)["jobDefinition"]; aws_config)
end

"""
    status(job::BatchJob) -> JobState

Returns the current status of a job.
"""
function status(job::BatchJob; aws_config::AbstractAWSConfig=global_aws_config())::JobState
    details = describe(job; aws_config)
    return parse(JobState, details["status"])
end

"""
    status_reason(job::BatchJob) -> Union{String, Nothing}

A short, human-readable string to provide additional details about the current status of the
job.
"""
function status_reason(job::BatchJob; aws_config::AbstractAWSConfig=global_aws_config())
    details = describe(job; aws_config)
    return get(details, "statusReason", nothing)
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
    delay=5,
    aws_config::AbstractAWSConfig=global_aws_config(),
)
    completed = false
    last_state = PENDING
    initial = true

    start_time = time()  # System time in seconds since epoch
    while time() - start_time < timeout
        state = status(job; aws_config)

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
        message = "Waiting on job $(job.id) timed out"

        if !initial
            message *= " Last known state $last_state"
        end

        throw(BatchJobError(job.id, message))
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
            throw(BatchJobError(job.id, "Job $(job.id) hit failure condition $state"))
            false
        else
            true
        end
    end
end


"""
    log_events(job::BatchJob) -> Union{Vector{LogEvent}, Nothing}

Fetches the logStreamName, fetches the CloudWatch logs, and returns a vector of log events.
If the log stream does not currently exist then `nothing` is returned.

NOTES:
- The `logStreamName` isn't available until the job is RUNNING, so you may want to use
  `wait(job)` or `wait(job, [AWSBatch.SUCCEEDED])` prior to calling this function.
"""
function log_events(job::BatchJob)
    job_details = describe(job)

    if haskey(job_details["container"], "logStreamName")
        stream = job_details["container"]["logStreamName"]
    else
        return nothing
    end

    info(logger, "Fetching log events from $stream")
    return log_events("/aws/batch/job", stream)
end

