"""
    JobDefinition

Stores the job definition arn including the revision.
"""
@auto_hash_equals struct JobDefinition
    arn::AbstractString

    function JobDefinition(name::AbstractString; aws_config::AbstractAWSConfig=global_aws_config())
        if startswith(name, "arn:")
            new(name)
        else
            arn = job_definition_arn(name; aws_config=aws_config)
            arn === nothing && error("No job definition ARN found for $name")
            new(arn)
        end
    end
end

"""
    job_definition_arn(
        definition_name::AbstractString;
        image::AbstractString="",
        role::AbstractString="",
        aws_config::AbstractAWSConfig=global_aws_config(),
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
    role::AbstractString="",
    aws_config::AbstractAWSConfig=global_aws_config(),
)
    response = describe_job_definition(definition_name; aws_config=aws_config)
    if !isempty(response["jobDefinitions"])

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
            info(
                logger,
                string(
                    "Found previously registered job definition: ",
                    "\"$(latest["jobDefinitionArn"])\"",
                )
            )
            return latest["jobDefinitionArn"]
        end
    end

    notice(
        logger,
        string(
            "Did not find a previously registered ACTIVE job definition for ",
            "\"$definition_name\".",
        )
    )
    return nothing
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
        parameters::Dict{String,String}=Dict{String, String}(),
    ) -> JobDefinition

Registers a new job definition.
"""
function register(
    definition_name::AbstractString;
    image::AbstractString="",
    role::AbstractString="",
    type::AbstractString="container",
    vcpus::Integer=1,
    memory::Integer=1024,
    cmd::Cmd=``,
    parameters::Dict{String, String}=Dict{String, String}(),
    aws_config::AbstractAWSConfig=global_aws_config(),
)
    debug(logger, "Registering job definition \"$definition_name\"")
    input = OrderedDict(
        "parameters" => parameters,
        "containerProperties" => OrderedDict(
            "image" => image,
            "vcpus" => vcpus,
            "memory" => memory,
            "command" => cmd.exec,
            "jobRoleArn" => role,
        ),
    )

    response = @mock Batch.register_job_definition(definition_name, type, input; aws_config=aws_config)
    definition = JobDefinition(response["jobDefinitionArn"]; aws_config=aws_config)
    info(logger, "Registered job definition \"$(definition.arn)\"")
    return definition
end

"""
    deregister(job::JobDefinition)

Deregisters an AWS Batch job.
"""
function deregister(definition::JobDefinition; aws_config::AbstractAWSConfig=global_aws_config())
    debug(logger, "Deregistering job definition \"$(definition.arn)\"")
    resp = @mock Batch.deregister_job_definition(definition.arn; aws_config=aws_config)
    info(logger, "Deregistered job definition \"$(definition.arn)\"")
end

"""
    isregistered(definition::JobDefinition; aws_config=global_aws_config()) -> Bool

Checks if a JobDefinition is registered.
"""
function isregistered(definition::JobDefinition; aws_config::AbstractAWSConfig=global_aws_config())
    j = describe(definition; aws_config=aws_config)
    return any(d -> d["status"] == "ACTIVE", get(j, "jobDefinitions", []))
end

"""
    list_job_definitions(;aws_config=global_aws_config())

Get a list of `JobDefinition` objects via `Batch.decsribe_job_definitions()`.
"""
function list_job_definitions(;aws_config::AbstractAWSConfig=global_aws_config())
    job_definitions = Batch.describe_job_definitions(; aws_config=aws_config)["jobDefinitions"]
    
    return [JobDefinition(jd["jobDefinitionArn"]) for jd in job_definitions]
end

"""
    describe(definition::JobDefinition; aws_config=global_aws_config()) -> Dict

Describes a job definition as a dictionary. Requires the IAM permissions
"batch:DescribeJobDefinitions".
"""
function describe(definition::JobDefinition; aws_config::AbstractAWSConfig=global_aws_config())
    describe_job_definition(definition; aws_config=aws_config)
end

function describe_job_definition(definition::JobDefinition;
                                 aws_config::AbstractAWSConfig=global_aws_config())
    describe_job_definition(definition.arn; aws_config=aws_config)
end
function describe_job_definition(definition::AbstractString;
                                 aws_config::AbstractAWSConfig=global_aws_config())
    query = if startswith(definition, "arn:")
        Dict("jobDefinitions" => [definition])
    else
        Dict("jobDefinitionName" => definition)
    end
    return @mock Batch.describe_job_definitions(query; aws_config=aws_config)
end
