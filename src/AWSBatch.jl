__precompile__()
module AWSBatch

using AWSSDK
using AWSSDK.Batch
using AWSSDK.CloudWatchLogs
using AWSSDK.S3

using Compat
using Memento
using Mocking

import Compat: Nothing

export
    BatchJob,
    JobDefinition,
    JobState,
    run_batch,
    describe,
    status,
    wait,
    log_events,
    isregistered,
    register,
    deregister


const logger = getlogger(current_module())
# Register the module level logger at runtime so that folks can access the logger via `getlogger(MyModule)`
# NOTE: If this line is not included then the precompiled `MyModule.logger` won't be registered at runtime.
__init__() = Memento.register(logger)


include("log_event.jl")
include("job_state.jl")
include("job_definition.jl")
include("batch_job.jl")


"""
    run_batch(;
        name::AbstractString="",
        queue::AbstractString="",
        region::AbstractString="",
        definition::Union{AbstractString, Nothing}=nothing,
        image::AbstractString="",
        vcpus::Integer=1,
        memory::Integer=1024,
        role::AbstractString="",
        cmd::Cmd=``,
    ) -> BatchJob

Handles submitting a BatchJob based on various potential defaults.
For example, default job fields can be inferred from an existing job definition or an
existing job (if currently running in a batch job).

Order of priority from highest to lowest:

1. Explict arguments passed in via `kwargs`.
2. Inferred environment (e.g., `AWS_BATCH_JOB_ID` environment variable set)
3. Job definition parameters

If no valid job definition exists (see [`AWSBatch.job_definition_arn`](@ref) then a new job
definition will be created and registered based on the job parameters.
"""
function run_batch(;
    name::AbstractString="",
    queue::AbstractString="",
    region::AbstractString="",
    definition::Union{AbstractString, Nothing}=nothing,
    image::AbstractString="",
    vcpus::Integer=1,
    memory::Integer=1024,
    role::AbstractString="",
    cmd::Cmd=``,
)
    if definition !== nothing
        definition = isempty(definition) ? nothing : JobDefinition(definition)
    end

    # Determine if the job definition already exists and update the default job parameters
    if definition !== nothing
        response = describe(definition)
        if !isempty(response["jobDefinitions"])
            details = first(response["jobDefinitions"])

            container = details["containerProperties"]
            isempty(image) && (image = container["image"])
            isempty(role) && (role = container["jobRoleArn"])

            # Update container override parameters
            vcpus == 1 && (vcpus = container["vcpus"])
            memory == 1024 && (memory = container["memory"])
            isempty(cmd) && (cmd = Cmd(Vector{String}(container["command"])))
        end
    end

    # Get inferred environment parameters
    if haskey(ENV, "AWS_BATCH_JOB_ID")
        # Environmental variables set by the AWS Batch service. They were discovered by
        # inspecting the running AWS Batch job in the ECS task interface.
        job_id = ENV["AWS_BATCH_JOB_ID"]
        job_queue = ENV["AWS_BATCH_JQ_NAME"]

        # Requires permissions to access to "batch:DescribeJobs"
        response = @mock describe_jobs(Dict("jobs" => [job_id]))

        # Use the job's description to only update fields that are using the default
        # values since explict arguments passed in via `kwargs` have higher priority
        if length(response["jobs"]) > 0
            details = first(response["jobs"])

            # Update the job's required parameters
            isempty(name) && (name = details["jobName"])
            definition === nothing && (definition = JobDefinition(details["jobDefinition"]))
            isempty(queue) && (queue = job_queue)

            # Update the container parameters
            container = details["container"]
            isempty(image) && (image = container["image"])
            isempty(role) && (role = container["jobRoleArn"])

            # Update container overrides
            vcpus == 1 && (vcpus = container["vcpus"])
            memory == 1024 && (memory = container["memory"])
            isempty(cmd) && (cmd = Cmd(Vector{String}(container["command"])))
        else
            warn(logger, "No jobs found with id: $job_id.")
        end
    end

    # Reuse a previously registered job definition if available.
    # If no job definition exists that can be reused, a new job definition is created
    # under the current job specifications.
    if definition !== nothing
        reusable_def = @mock job_definition_arn(definition; image=image, role=role)

        if reusable_def !== nothing
            definition = reusable_def
        else
            definition = @mock register(
                definition.name;
                image=image,
                role=role,
                vcpus=vcpus,
                memory=memory,
                cmd=cmd,
            )
        end
    else
        # Use the job name as the definiton name since the definition name was not specified
        definition = @mock register(
            name;
            image=image,
            role=role,
            vcpus=vcpus,
            memory=memory,
            cmd=cmd,
        )
    end

    # The parameters that can be overridden are `memory`, `vcpus`, `cmd`, and `environment`
    # See https://docs.aws.amazon.com/batch/latest/APIReference/API_ContainerOverrides.html
    container_overrides = Dict(
        "vcpus" => vcpus,
        "memory" => memory,
        "cmd" => cmd,
    )

    return @mock submit(name, definition, queue; container=container_overrides)
end

include("deprecated.jl")

end  # AWSBatch
