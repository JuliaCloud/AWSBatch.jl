@testset "BatchJob" begin
    job = BatchJob("00000000-0000-0000-0000-000000000000")

    @testset "status_reason" begin
        @testset "not provided" begin
            patch = @patch function describe_jobs(; kwargs...)
                Dict(
                    "jobs" => [
                        Dict()
                    ]
                )
            end

            apply(patch) do
                @test status_reason(job) === nothing
            end
        end

        @testset "provided" begin
            reason = "Essential container in task exited"
            patch = @patch function describe_jobs(; kwargs...)
                Dict(
                    "jobs" => [
                        Dict("statusReason" => reason)
                    ]
                )
            end

            apply(patch) do
                @test status_reason(job) == reason
            end
        end
    end

    @testset "log_events" begin
        @testset "Stream not yet created" begin
            # When a AWS Batch job is first submitted the description of the job will not
            # contain a reference to a log stream
            patches = log_events_patches(log_stream_name=nothing)
            apply(patches) do
                @test log_events(job) === nothing
            end
        end
    end
end
