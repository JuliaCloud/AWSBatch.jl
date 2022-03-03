module AWSBatch

using AWS
using AutoHashEquals
using OrderedCollections: OrderedDict
using Dates
using Memento
using Mocking

@service Batch
@service Cloudwatch_Logs

export BatchJob, ComputeEnvironment, BatchEnvironmentError, BatchJobError
export JobQueue, JobDefinition, JobState, LogEvent
export run_batch,
    describe, status, status_reason, wait, log_events, isregistered, register, deregister
export list_job_queues, list_job_definitions, create_compute_environment, create_job_queue
export terminate_jobs

const logger = getlogger(@__MODULE__)
# Register the module level logger at runtime so that folks can access the logger via `getlogger(MyModule)`
# NOTE: If this line is not included then the precompiled `MyModule.logger` won't be registered at runtime.
__init__() = Memento.register(logger)

include("exceptions.jl")
include("log_event.jl")
include("compute_environment.jl")
include("job_queue.jl")
include("job_state.jl")
include("job_definition.jl")
include("batch_job.jl")
include("utilities.jl")

"""
    run_batch(;
        name::AbstractString="",
        queue::AbstractString="",
        region::AbstractString="",
        definition::Union{AbstractString, JobDefinition, Nothing}=nothing,
        image::AbstractString="",
        vcpus::Integer=1,
        memory::Integer=-1,
        role::AbstractString="",
        cmd::Cmd=``,
        num_jobs::Integer=1,
        parameters::Dict{String, String}=Dict{String, String}(),
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
    definition::Union{AbstractString,JobDefinition,Nothing}=nothing,
    image::AbstractString="",
    vcpus::Integer=1,
    memory::Integer=-1,
    role::AbstractString="",
    cmd::Cmd=``,
    num_jobs::Integer=1,
    parameters::Dict{String,String}=Dict{String,String}(),
    allow_job_registration::Bool=true,
    aws_config::AbstractAWSConfig=global_aws_config(),
)
    if isa(definition, AbstractString)
        definition = isempty(definition) ? nothing : definition
    end

    # Determine if the job definition already exists and update the default job parameters
    if definition !== nothing
        response = describe_job_definition(definition; aws_config=aws_config)
        if !isempty(response["jobDefinitions"])
            details = first(response["jobDefinitions"])

            container = details["containerProperties"]
            isempty(image) && (image = container["image"])
            isempty(role) && (role = container["jobRoleArn"])

            # Update container override parameters
            vcpus == 1 && (vcpus = container["vcpus"])
            memory < 0 && (memory = container["memory"])
            isempty(cmd) && (cmd = Cmd(Vector{String}(container["command"])))
        end
    end

    # Get inferred environment parameters
    if haskey(ENV, "AWS_BATCH_JOB_ID")
        # Environmental variables set by the AWS Batch service. They were discovered by
        # inspecting the running AWS Batch job in the ECS task interface.
        job_id = ENV["AWS_BATCH_JOB_ID"]
        job_queue = ENV["AWS_BATCH_JQ_NAME"]

        # if not specified, get region from the aws_config
        isempty(region) && (region = aws_config.region)

        # Requires permissions to access to "batch:DescribeJobs"
        response = @mock Batch.describe_jobs([job_id]; aws_config=aws_config)

        # Use the job's description to only update fields that are using the default
        # values since explict arguments passed in via `kwargs` have higher priority
        if length(response["jobs"]) > 0
            details = first(response["jobs"])

            # Update the job's required parameters
            isempty(name) && (name = details["jobName"])
            definition === nothing && (definition = details["jobDefinition"])
            isempty(queue) && (queue = job_queue)

            # Update the container parameters
            container = details["container"]
            isempty(image) && (image = container["image"])
            isempty(role) && (role = container["jobRoleArn"])

            # Update container overrides
            vcpus == 1 && (vcpus = container["vcpus"])
            memory < 0 && (memory = container["memory"])
            isempty(cmd) && (cmd = Cmd(Vector{String}(container["command"])))
        else
            warn(logger, "No jobs found with id: $job_id.")
        end
    end

    # Error if required parameters were not explicitly set and cannot be inferred
    if isempty(name) || isempty(queue) || memory < 0
        throw(
            BatchEnvironmentError(
                "Unable to perform AWS Batch introspection when not running within " *
                "an AWS Batch job. Current job parameters are: " *
                "\nname=$name" *
                "\nqueue=$queue" *
                "\nmemory=$memory",
            ),
        )
    end

    # Reuse a previously registered job definition if available.
    if isa(definition, AbstractString)
        reusable_job_definition_arn = job_definition_arn(definition; image=image, role=role)

        if reusable_job_definition_arn !== nothing
            definition = JobDefinition(reusable_job_definition_arn)
        end
    elseif definition === nothing
        # Use the job name as the definiton name since the definition name was not specified
        definition = name
    end

    # If no job definition exists that can be reused, a new job definition is created
    # under the current job specifications.
    if isa(definition, AbstractString)
        if allow_job_registration
            definition = register(
                definition;
                image=image,
                role=role,
                vcpus=vcpus,
                memory=memory,
                cmd=cmd,
                parameters=parameters,
                aws_config=aws_config,
            )
        else
            throw(
                BatchEnvironmentError(
                    string(
                        "Attempting to register job definition \"$definition\" but registering ",
                        "job definitions is disallowed. Current job definition parameters are: ",
                        "\nimage=$image",
                        "\nrole=$role",
                        "\nvcpus=$vcpus",
                        "\nmemory=$memory",
                        "\ncmd=$cmd",
                        "\nparameters=$parameters",
                    ),
                ),
            )
        end
    end

    # Parameters that can be overridden are `memory`, `vcpus`, `command`, and `environment`
    # See https://docs.aws.amazon.com/batch/latest/APIReference/API_ContainerOverrides.html
    container_overrides = Dict("vcpus" => vcpus, "memory" => memory, "command" => cmd.exec)

    return submit(
        name,
        definition,
        JobQueue(queue);
        container=container_overrides,
        parameters=parameters,
        num_jobs=num_jobs,
    )
end

end  # AWSBatch
