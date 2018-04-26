import AWSSDK.Batch:
    describe_job_definitions, register_job_definition, deregister_job_definition

"""
    JobDefinition

Stores the job definition name or arn including the revision.
"""
struct JobDefinition
    name::AbstractString
end

"""
    register(
        definition::AbstractString;
        role::AbstractString="",
        image::AbstractString="",
        vcpus::Integer=1,
        memory::Integer=1024,
        cmd::Cmd=``,
        region::AbstractString="",
    ) -> JobDefinition

Registers a new job definition.
"""
function register(
    definition::AbstractString;
    image::AbstractString="",
    role::AbstractString="",
    vcpus::Integer=1,
    memory::Integer=1024,
    cmd::Cmd=``,
    region::AbstractString="",
)
    region = isempty(region) ? "us-east-1" : region
    config = AWSConfig(:creds => AWSCredentials(), :region => region)

    debug(logger, "Registering job definition $definition.")
    input = [
        "type" => "container",
        "containerProperties" => [
            "image" => image,
            "vcpus" => vcpus,
            "memory" => memory,
            "command" => cmd.exec,
            "jobRoleArn" => role,
        ],
        "jobDefinitionName" => definition,
    ]

    response = @mock register_job_definition(config, input)
    definition = JobDefinition(response["jobDefinitionArn"])
    info(logger, "Registered job definition $(definition.name).")
    return definition
end

"""
    job_definition_arn(
        definition::JobDefinition;
        image::AbstractString="",
        role::AbstractString=""
    ) -> Union{JobDefinition, Nothing}

Looks up the ARN (Amazon Resource Name) for the latest job definition that can be reused.
Returns a JobDefinition with the ARN that can be reused or `nothing`.

A job definition can only be reused if:

1. status = ACTIVE
2. type = container
3. image = the current job's image
4. jobRoleArn = the current job's role
"""
function job_definition_arn(
    definition::JobDefinition;
    image::AbstractString="",
    role::AbstractString=""
)
    response = describe(definition)
    isempty(response["jobDefinitions"]) && return nothing

    latest = first(response["jobDefinitions"])
    for definition in response["jobDefinitions"]
        if definition["status"] == "ACTIVE" && definition["revision"] > latest["revision"]
            latest = definition
        end
    end
    if (
        latest["status"] == "ACTIVE" &&
        latest["type"] == "container" &&
        (latest["containerProperties"]["image"] == image || isempty(image)) &&
        (latest["containerProperties"]["jobRoleArn"] == role || isempty(role))
    )
        return JobDefinition(latest["jobDefinitionArn"])
    else
        return nothing
    end
end

"""
    deregister(job::JobDefinition)

Deregisters an AWS Batch job.
"""
function deregister(definition::JobDefinition)
    debug(logger, "Deregistering job definition $(definition.name).")
    resp = deregister_job_definition(Dict("jobDefinition" => definition.name))
    info(logger, "Deregistered job definition $(definition.name).")
end

"""
    isregistered(definition::JobDefinition) -> Bool

Checks if a JobDefinition is registered.
"""
function isregistered(definition::JobDefinition)
    j = describe(definition)
    active_definitions = filter!(d -> d["status"] == "ACTIVE", get(j, "jobDefinitions", []))
    return !isempty(active_definitions)
end

"""
    describe(definition::JobDefinition) -> Dict

Describes a job given it's definition. Returns the response dictionary.
Requires permissions to access "batch:DescribeJobDefinitions".
"""
function describe(definition::JobDefinition)
    if startswith(definition.name, "arn:")
        return @mock describe_job_definitions(Dict("jobDefinitions" => [definition.name]))
    else
        return @mock describe_job_definitions(Dict("jobDefinitionName" => definition.name))
    end
end
