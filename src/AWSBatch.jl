__precompile__()
module AWSBatch

using AWSSDK
using AWSSDK.Batch
using AWSSDK.CloudWatchLogs
using AWSSDK.S3

using Compat
using Memento
using Mocking

import AWSSDK.Batch:
    describe_job_definitions, describe_jobs, register_job_definition,
    deregister_job_definition, submit_job

import AWSSDK.CloudWatchLogs: get_log_events

import Compat: Nothing

export
    BatchJob,
    BatchJobDefinition,
    BatchJobContainer,
    JobState,
    isregistered,
    register!,
    deregister!,
    submit!,
    describe,
    status,
    wait,
    logs,
    log_events


const logger = getlogger(current_module())
# Register the module level logger at runtime so that folks can access the logger via `getlogger(MyModule)`
# NOTE: If this line is not included then the precompiled `MyModule.logger` won't be registered at runtime.
__init__() = Memento.register(logger)


include("log_event.jl")
include("job_state.jl")

##################################
#       BatchJobContainer
##################################

"""
    BatchJob

Stores configuration information about a batch job's container properties.

# Fields
- image::String: the ECR container image to use for the ECS task
- vcpus::Int: # of cpus available in the ECS task container
- memory::Int: memory allocated to the ECS task container (in MB)
- role::String: IAM role to apply to the ECS task
- cmd::Cmd: command to execute in the batch job
"""
struct BatchJobContainer
    image::String
    vcpus::Int
    memory::Int
    role::String
    cmd::Cmd
end

##################################
#       BatchJobDefinition
##################################

"""
    BatchJobDefinition

Stores the job definition name or arn including the revision.
"""
struct BatchJobDefinition
    name::AbstractString
end

"""
    describe(definition::BatchJobDefinition)

Describes a job given it's definition. Returns the response dictionary.
Requires permissions to access "batch:DescribeJobDefinitions".
"""
function describe(definition::BatchJobDefinition)
    if startswith(definition.name, "arn:")
        return describe_job_definitions(Dict("jobDefinitions" => [definition.name]))
    else
        return @mock describe_job_definitions(Dict("jobDefinitionName" => definition.name))
    end
end

"""
    isregistered(definition::BatchJobDefinition)

Checks if a BatchJobDefinition is registered.
"""
function isregistered(definition::BatchJobDefinition)
    j = describe(definition)
    active_definitions = filter!(d -> d["status"] == "ACTIVE", get(j, "jobDefinitions", []))
    return !isempty(active_definitions)
end

##################################
#            BatchJob
##################################

"""
    BatchJob

Stores configuration information about a batch job in order to:

- `register` a new job definition
- `submit` a new job to batch
- `describe` a batch job
- check if a batch job definition `isregistered`
- `deregister` a job definition
- `wait` for a job to complete
- fetch `logs`

# Fields
- id::String: jobId
- name:String: jobName
- definition::Union{BatchJobDefinition, Nothing}: job definition
- queue::String: queue to insert the batch job into
- region::String: AWS region to use
- container::BatchJobContainer: job container properties (image, vcpus, memory, role, cmd)
"""
mutable struct BatchJob
    id::String
    name::String
    definition::Union{BatchJobDefinition, Nothing}
    queue::String
    region::String
    container::BatchJobContainer
end

"""
    BatchJob(;
        id::String="",
        name::String="",
        queue::String="",
        region::String="",
        definition::Union{String, Nothing}=nothing,
        image::String="",
        vcpus::Integer=1,
        memory::Integer=1024,
        role::String="",
        cmd::Cmd=``,
    )

Handles creating a BatchJob based on various potential defaults.
For example, default job fields can be inferred from an existing job defintion or existing
job (if currently running in a batch job)

Order of priority from lowest to highest:

1. Job definition parameters
2. Inferred environment (e.g., `AWS_BATCH_JOB_ID` environment variable set)
3. Explict arguments passed in via `kwargs`.
"""
function BatchJob(;
    id::String="",
    name::String="",
    queue::String="",
    region::String="",
    definition::Union{String, Nothing}=nothing,
    image::String="",
    vcpus::Integer=1,
    memory::Integer=1024,
    role::String="",
    cmd::Cmd=``,
)

    if definition !== nothing
        definition = isempty(definition) ? nothing : BatchJobDefinition(definition)
    end

    # Determine if the job definition already exists and update it
    if definition !== nothing
        resp = describe(definition)
        if !isempty(resp["jobDefinitions"])
            details = first(resp["jobDefinitions"])

            # Only update fields that are using the default values since explict arguments
            # passed in have priority over aws job definition parameters
            container = details["containerProperties"]
            isempty(image) && (image = container["image"])
            vcpus == 1 && (vcpus = container["vcpus"])
            memory == 1024 && (memory = container["memory"])
            isempty(role) && (role = container["jobRoleArn"])
            isempty(cmd) && (cmd = Cmd(Vector{String}(container["command"])))
        end
    end

    if haskey(ENV, "AWS_BATCH_JOB_ID")
        # Environmental variables set by the AWS Batch service. They were discovered by
        # inspecting the running AWS Batch job in the ECS task interface.
        job_id = ENV["AWS_BATCH_JOB_ID"]
        job_queue = ENV["AWS_BATCH_JQ_NAME"]

        # Get the zone information from the EC2 instance metadata.
        zone = @mock readstring(
            pipeline(
                `curl http://169.254.169.254/latest/meta-data/placement/availability-zone`;
                stderr=DevNull
            )
        )
        job_region = chop(zone)

        # Requires permissions to access to "batch:DescribeJobs"
        resp = @mock describe_jobs(Dict("jobs" => [job_id]))

        if length(resp["jobs"]) > 0
            details = first(resp["jobs"])

            isempty(id) && (id = job_id)
            isempty(name) && (name = details["jobName"])
            isempty(queue) && (queue = job_queue)
            isempty(region) && (region = job_region)
            if definition === nothing
                definition = BatchJobDefinition(details["jobDefinition"])
            end

            # Only update fields that are using the default values since explict arguments
            # passed in have priority over aws job definition parameters
            container = details["container"]
            isempty(image) && (image = container["image"])
            vcpus == 1 && (vcpus = container["vcpus"])
            memory == 1024 && (memory = container["memory"])
            isempty(role) && (role = container["jobRoleArn"])
            isempty(cmd) && (cmd = Cmd(Vector{String}(container["command"])))
        else
            warn(logger, "No jobs found with id: $job_id.")
        end
    end

    job_container = BatchJobContainer(image, vcpus, memory, role, cmd)
    return BatchJob(id, name, definition, queue, region, job_container)
end

"""
    isregistered(job::BatchJob) -> Bool

Checks if a job is registered. If no job definition exists, a new job definition is created
under the current job specifications, where the new job definition will be `job.name`.
"""
function isregistered(job::BatchJob)
    return job.definition !== nothing && isregistered(job.definition)
end

"""
    register!(job::BatchJob)

Registers a new job definition. If no job definition exists, a new job definition is created
under the current job specifications, where the new job definition will be `job.name`.
"""
function register!(job::BatchJob)
    job.definition === nothing && (job.definition = BatchJobDefinition(job.name))

    debug(logger, "Registering job definition $(job.definition.name).")
    input = [
        "type" => "container",
        "containerProperties" => [
            "image" => job.container.image,
            "vcpus" => job.container.vcpus,
            "memory" => job.container.memory,
            "command" => job.container.cmd.exec,
            "jobRoleArn" => job.container.role,
        ],
        "jobDefinitionName" => job.definition.name,
    ]

    resp = register_job_definition(input)
    job.definition = BatchJobDefinition(resp["jobDefinitionArn"])
    info(logger, "Registered job definition $(job.definition.name).")
end

"""
    deregister!(job::BatchJob)

Deregisters an AWS Batch job. If no job definition exists, a new job definition is created
under the current job specifications, where the new job definition will be `job.name`.
"""
function deregister!(job::BatchJob)
    job.definition === nothing && (job.definition = BatchJobDefinition(job.name))
    debug(logger, "Deregistering job definition $(job.definition.name).")
    resp = deregister_job_definition(Dict("jobDefinition" => job.definition.name))
    info(logger, "Deregistered job definition $(job.definition.name).")
end

"""
    submit!(job::BatchJob) -> Dict

Handles submitting the batch job and registering a new job definition if necessary.
If no valid job definition exists (see `AWSBatch.job_definition_arn`) then a new job
definition will be created. Once the job has been submitted this function will return the
response dictionary.
"""
function submit!(job::BatchJob)
    definition = job_definition_arn(job)

    if definition === nothing
        register!(job)
    else
        job.definition = BatchJobDefinition(definition)
    end

    debug(logger, "Submitting job $(job.name).")
    input = [
        "jobName" => job.name,
        "jobDefinition" => job.definition.name,
        "jobQueue" => job.queue,
        "containerOverrides" => [
            "vcpus" => job.container.vcpus,
            "memory" => job.container.memory,
            "command" => job.container.cmd.exec,
        ]
    ]
    debug(logger, "Input: $input")
    resp = submit_job(input)

    job.id = resp["jobId"]
    info(logger, "Submitted job $(job.name)::$(job.id).")

    return resp
end

"""
    describe(job::BatchJob) -> Dict

If job.id is set then this function is simply responsible for fetch a dictionary for
describing the batch job.
"""
function describe(job::BatchJob)
    # Make sure the job.id has been set
    if isempty(job.id)
        error(
            logger,
            ArgumentError("job.id has not been set, call `submit!` to set it first.")
        )
    end

    # Get AWS job description
    resp = describe_jobs(; jobs=[job.id])
    isempty(resp["jobs"]) && error(logger, "Job $(job.name)::$(job.id) not found.")
    debug(logger, "Job $(job.name)::$(job.id): $resp")
    return first(resp["jobs"])
end

"""
    job_definition_arn(job::BatchJob) -> Union{String, Nothing}

Looks up the ARN (Amazaon Resource Name) for the latest job definition that can be reused
for the current `BatchJob`. A job definition can only be reused if:

1. status = ACTIVE
2. type = container
3. image = job.container.image
4. jobRoleArn = job.container.role
"""
function job_definition_arn(job::BatchJob)::Union{String, Nothing}
    job.definition === nothing && return nothing

    resp = describe(job.definition)
    isempty(resp["jobDefinitions"]) && return nothing

    latest = first(resp["jobDefinitions"])
    for definition in resp["jobDefinitions"]
        if definition["status"] == "ACTIVE" && definition["revision"] > latest["revision"]
            latest = definition
        end
    end

    if (
        latest["status"] == "ACTIVE" &&
        latest["type"] == "container" &&
        latest["containerProperties"]["image"] == job.container.image &&
        latest["containerProperties"]["jobRoleArn"] == job.container.role
    )
        return latest["jobDefinitionArn"]
    else
        return nothing
    end
end

""" status(job::BatchJob) -> JobState

Returns the current status of a BatchJob.  # TODO: add to autodocs
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
            info(logger, "$(job.name)::$(job.id) status $state")

            if !cond(state)
                completed = true
                break
            end

            last_state = state
        end

        initial = false
        sleep(delay)
    end

    if !completed
        message = "Waiting on job $(job.name)::$(job.id) timed out."

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
        timeout=600,
        delay=5
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
            error(logger, "Job $(job.name)::$(job.id) hit failure condition $state.")
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
        info(logger, "No log events found for job $(job.name)::$(job.id).")
        return LogEvent[]
    end
end

include("deprecated.jl")

end  # AWSBatch
