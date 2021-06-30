struct JobQueue
    arn::String

    function JobQueue(queue::AbstractString; aws_config::AbstractAWSConfig=global_aws_config())
        arn = job_queue_arn(queue; aws_config)
        arn === nothing && error("No job queue ARN found for: $queue")
        new(arn)
    end
end

Base.:(==)(a::JobQueue, b::JobQueue) = a.arn == b.arn
function describe(queue::JobQueue; aws_config::AbstractAWSConfig=global_aws_config())
    return describe_job_queue(queue; aws_config)
end
function describe_job_queue(queue::JobQueue; aws_config::AbstractAWSConfig=global_aws_config())
    return describe_job_queue(queue.arn; aws_config)
end
function max_vcpus(queue::JobQueue; aws_config::AbstractAWSConfig=global_aws_config())
    sum(max_vcpus(ce; aws_config) for ce in compute_environments(queue; aws_config))
end

function _create_compute_environment_order(envs)
    map(enumerate(envs)) do (i, env)
        Dict{String,Any}("computeEnvironment"=>env, "order"=>i)
    end
end

"""
    create_job_queue(name, envs, priority=1; aws_config=global_aws_config())

Create a job queue with name `name` and priority `priority` returning the associated `JobQueue` object.
`envs` must be an iterator of compute environments given by ARN.

See the AWS docs [here](https://docs.aws.amazon.com/batch/latest/APIReference/API_CreateJobQueue.html).
"""
function create_job_queue(name::AbstractString, envs, priority::Integer=1;
                          enabled::Bool=true,
                          tags::AbstractDict=Dict{String,Any}(),
                          aws_config::AbstractAWSConfig=global_aws_config())
    env = _create_compute_environment_order(envs)
    args = Dict{String,Any}()
    enabled || (args["state"] = "DISABLED")
    isempty(tags) || (args["tags"] = tags)
    return @mock Batch.create_job_queue(env, name, priority, args; aws_config=aws_config)
end


"""
    list_job_queues(;aws_config=global_aws_config())

Get a list of `JobQueue` objects as returned by `Batch.describe_job_queues()`.
"""
function list_job_queues(;aws_config::AbstractAWSConfig=global_aws_config())
    [JobQueue(q["jobQueueArn"]) for q ∈ Batch.describe_job_queues(;aws_config)["jobQueues"]]
end


"""
    compute_environments(queue::JobQueue; aws_config=global_aws_config())

Get a list of `ComputeEnvironment` objects associated with the `JobQueue`.
"""
function compute_environments(queue::JobQueue; aws_config::AbstractAWSConfig=global_aws_config())
    ce_order = describe(queue; aws_config)["computeEnvironmentOrder"]

    compute_envs = Vector{ComputeEnvironment}(undef, length(ce_order))
    for ce in ce_order
        i, arn = ce["order"], ce["computeEnvironment"]
        compute_envs[i] = ComputeEnvironment(arn)
    end

    return compute_envs
end


function job_queue_arn(queue::AbstractString; aws_config::AbstractAWSConfig=global_aws_config())
    startswith(queue, "arn:") && return queue
    json = describe_job_queue(queue; aws_config)
    isempty(json) ? nothing : json["jobQueueArn"]
end


function describe_job_queue(queue::AbstractString;
                            aws_config::AbstractAWSConfig=global_aws_config())::OrderedDict
    json = @mock Batch.describe_job_queues(Dict("jobQueues" => [queue]); aws_config=aws_config)
    queues = json["jobQueues"]
    len = length(queues)::Int
    @assert len <= 1
    return len == 1 ? first(queues) : OrderedDict()
end
