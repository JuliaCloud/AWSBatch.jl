import AWSSDK.Batch:
    describe_job_definitions, register_job_definition, deregister_job_definition

"""
    JobDefinition

Stores the job definition arn including the revision.
"""
struct JobDefinition
    arn::AbstractString

    function JobDefinition(name::AbstractString)
        if startswith(name, "arn:")
            new(name)
        else
            arn = job_definition_arn(name)
            arn === nothing && error("No job definition ARN found for $name")
            new(arn)
        end
    end
end

"""
    job_definition_arn(
        definition_name::AbstractString;
        image::AbstractString="",
        role::AbstractString=""
    ) -> Union{AbstractString, Nothing}

Looks up the ARN (Amazon Resource Name) for the latest job definition that can be reused.
Returns a JobDefinition with the ARN that can be reused or `nothing`.

A job definition can only be reused if:

1. status = ACTIVE
2. type = container
3. image = the current job's image
4. jobRoleArn = the current job's role
"""
function job_definition_arn(
    definition_name::AbstractString;
    image::AbstractString="",
    role::AbstractString=""
)
    response = describe_job_definition(definition_name)
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
        return latest["jobDefinitionArn"]
    else
        return nothing
    end
end

"""
    register(
        definition_name::AbstractString;
        role::AbstractString="",
        image::AbstractString="",
        vcpus::Integer=1,
        memory::Integer=1024,
        cmd::Cmd=``,
        region::AbstractString="",
        parameters::Dict{String,String} = Dict{String, String}(),
    ) -> JobDefinition

Registers a new job definition.
"""
function register(
    definition_name::AbstractString;
    image::AbstractString="",
    role::AbstractString="",
    vcpus::Integer=1,
    memory::Integer=1024,
    cmd::Cmd=``,
    region::AbstractString="",
    parameters::Dict{String, String} = Dict{String, String}(),
)
    region = isempty(region) ? "us-east-1" : region
    config = AWSConfig(:creds => AWSCredentials(), :region => region)

    debug(logger, "Registering job definition \"$definition_name\"")
    input = [
        "type" => "container",
        "parameters" => parameters,
        "containerProperties" => [
            "image" => image,
            "vcpus" => vcpus,
            "memory" => memory,
            "command" => cmd.exec,
            "jobRoleArn" => role,
        ],
        "jobDefinitionName" => definition_name,
    ]

    response = @mock register_job_definition(config, input)
    definition = JobDefinition(response["jobDefinitionArn"])
    info(logger, "Registered job definition \"$(definition.arn)\"")
    return definition
end

"""
    deregister(job::JobDefinition)

Deregisters an AWS Batch job.
"""
function deregister(definition::JobDefinition)
    debug(logger, "Deregistering job definition \"$(definition.arn)\"")
    resp = deregister_job_definition(Dict("jobDefinition" => definition.arn))
    info(logger, "Deregistered job definition \"$(definition.arn)\"")
end

"""
    isregistered(definition::JobDefinition) -> Bool

Checks if a JobDefinition is registered.
"""
function isregistered(definition::JobDefinition)
    j = describe(definition)
    return any(d -> d["status"] == "ACTIVE", get(j, "jobDefinitions", []))
end

"""
    describe(definition::JobDefinition) -> Dict

Describes a job definition as a dictionary. Requires the IAM permissions
"batch:DescribeJobDefinitions".
"""
describe(definition::JobDefinition) = describe_job_definition(definition)

describe_job_definition(definition::JobDefinition) = describe_job_definition(definition.arn)
function describe_job_definition(definition::AbstractString)
    query = if startswith(definition, "arn:")
        Dict("jobDefinitions" => [definition])
    else
        Dict("jobDefinitionName" => definition)
    end
    return @mock describe_job_definitions(query)
end
