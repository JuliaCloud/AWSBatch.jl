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
    describe_job_queue(queue; aws_config)
end
function describe_job_queue(queue::JobQueue; aws_config::AbstractAWSConfig=global_aws_config())
    describe_job_queue(queue.arn; aws_config)
end
function max_vcpus(queue::JobQueue; aws_config::AbstractAWSConfig=global_aws_config())
    sum(max_vcpus(ce; aws_config) for ce in compute_environments(queue; aws_config))
end

# TODO the below is not done, it needs compute environemnt
"""
    create_job_queue(name, priority=1; aws_config=global_aws_config())

Create a job queue with name `name` and priority `priority` returning the associated `JobQueue` object.
"""
function create_job_queue(name::AbstractString, priority::Integer=1;
                          aws_config::AbstractAWSConfig=global_aws_config())
    # TODO this needs to return a JobQueue object
    return @mock Batch.create_job_queue(["container"], name, priority; aws_config=aws_config)
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
        # AWS is using 0-based indexing, so we must translate
        compute_envs[i+1] = ComputeEnvironment(arn)
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
