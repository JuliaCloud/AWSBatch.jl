@testset "BatchJob" begin
    job = BatchJob("00000000-0000-0000-0000-000000000000")

    @testset "status_reason" begin
        @testset "not provided" begin
            patch = @patch function AWSBatch.Batch.describe_jobs(args...; kwargs...)
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
            patch = @patch function AWSBatch.Batch.describe_jobs(args...; kwargs...)
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

    @testset "wait" begin
        # Generate a patch which returns the next status each time it is requested
        function status_patch(states)
            index = 1

            return @patch function AWSBatch.Batch.describe_jobs(args...; kwargs...)
                json = Dict(
                    "jobs" => [
                        Dict("status" => states[index])
                    ]
                )

                if index < length(states)
                    index += 1
                end

                return json
            end
        end

        @testset "success" begin
            # Encounter all states possible for a successful job
            states = ["SUBMITTED", "PENDING", "RUNNABLE", "STARTING", "RUNNING", "SUCCEEDED"]
            apply(status_patch(states)) do
                @test_log logger "info" r"^[\d-]+ status \w+" begin
                    @test wait(state -> state < AWSBatch.SUCCEEDED, job; delay=0.1) == true
                end
                @test status(job) == AWSBatch.SUCCEEDED
            end
        end

        @testset "failed" begin
            # Encounter all states possible for a failed job
            states = ["SUBMITTED", "PENDING", "RUNNABLE", "STARTING", "RUNNING", "FAILED"]
            apply(status_patch(states)) do
                @test_log logger "info" r"^[\d-]+ status \w+" begin
                    @test wait(state -> state < AWSBatch.SUCCEEDED, job; delay=0.1) == true
                end
                @test status(job) == AWSBatch.FAILED
            end
        end

        @testset "timeout" begin
            apply(status_patch(["SUBMITTED", "RUNNING", "SUCCEEDED"])) do
                started = time()
                @test_nolog logger "info" r".*" begin
                    @test_throws BatchJobError wait(
                        state -> state < AWSBatch.SUCCEEDED,
                        job;
                        delay=0.1,
                        timeout=0
                    )
                end
                duration = time() - started
                @test status(job) != AWSBatch.SUCCEEDED  # Requires a minimum of 3 states
                @test duration < 1  # Less than 1 second
            end
        end
    end
end
