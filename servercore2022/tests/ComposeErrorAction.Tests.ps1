Describe 'SBS_ENTRYPOINTERRORACTION behavior' {
    BeforeAll {
        . ./../bootstraptest.ps1
    }

    Context 'Sync mode with SBS_ENTRYPOINTERRORACTION=Stop' {
        BeforeAll {
            $Env:ImageName = "servercore2022-servercore-1"
        }

        It 'Container fails when error occurs (Stop mode)' {
            docker compose -f servercore2022/compose-erroraction-stop-sync.yaml up -d;
            
            # Wait for the error to occur
            WaitForLog $Env:ImageName "0000_TestError.ps1" -extendedTimeout
            
            # In Stop mode, the container should exit with a non-zero exit code
            # Wait for container to exit
            WaitForContainerStatus $Env:ImageName "Exited" -extendedTimeout
            
            # Verify exit code is non-zero (error)
            $exitCode = docker inspect $Env:ImageName --format='{{.State.ExitCode}}'
            [int]$exitCode | Should -Not -Be 0
        }

        It 'Error message is logged' {
            WaitForLog $Env:ImageName "Forced error due to environment variable SBS_TESTERROR" -extendedTimeout
        }

        AfterAll {
            docker compose -f servercore2022/compose-erroraction-stop-sync.yaml down;
        }
    }

    Context 'Sync mode with SBS_ENTRYPOINTERRORACTION=Continue' {
        BeforeAll {
            $Env:ImageName = "servercore2022-servercore-1"
        }

        It 'Container continues initialization despite error (Continue mode)' {
            docker compose -f servercore2022/compose-erroraction-continue-sync.yaml up -d;
            
            # Wait for the error to occur
            WaitForLog $Env:ImageName "0000_TestError.ps1" -extendedTimeout
            
            # In Continue mode, the container should complete initialization despite the error
            WaitForLog $Env:ImageName "Initialization completed" -extendedTimeout
        }

        It 'Error is logged but does not stop execution' {
            WaitForLog $Env:ImageName "Forced error due to environment variable SBS_TESTERROR" -extendedTimeout
            WaitForLog $Env:ImageName "SbsRunScriptsInDirectory completed" -extendedTimeout
        }

        It 'Container stays running' {
            $status = docker ps --filter "name=$Env:ImageName" --format "{{.Status}}"
            $status | Should -Match "Up"
        }

        AfterAll {
            docker compose -f servercore2022/compose-erroraction-continue-sync.yaml down;
        }
    }

    Context 'Async mode with SBS_ENTRYPOINTERRORACTION=Stop' {
        BeforeAll {
            $Env:ImageName = "servercore2022-servercore-1"
        }

        It 'Container fails when error occurs (Stop mode, Async)' {
            docker compose -f servercore2022/compose-erroraction-stop-async.yaml up -d;
            
            # Wait for the error to occur
            WaitForLog $Env:ImageName "0000_TestError.ps1" -extendedTimeout
            
            # In Stop mode, the container should exit with a non-zero exit code
            # Wait for container to exit
            WaitForContainerStatus $Env:ImageName "Exited" -extendedTimeout
            
            # Verify exit code is non-zero (error)
            $exitCode = docker inspect $Env:ImageName --format='{{.State.ExitCode}}'
            [int]$exitCode | Should -Not -Be 0
        }

        It 'Error message is logged' {
            WaitForLog $Env:ImageName "Forced error due to environment variable SBS_TESTERROR" -extendedTimeout
        }

        It 'Async initialization mode is used' {
            WaitForLog $Env:ImageName "init scripts asynchronously" -extendedTimeout
        }

        AfterAll {
            docker compose -f servercore2022/compose-erroraction-stop-async.yaml down;
        }
    }

    Context 'Async mode with SBS_ENTRYPOINTERRORACTION=Continue' {
        BeforeAll {
            $Env:ImageName = "servercore2022-servercore-1"
        }

        It 'Container continues initialization despite error (Continue mode, Async)' {
            docker compose -f servercore2022/compose-erroraction-continue-async.yaml up -d;
            
            # Wait for the error to occur
            WaitForLog $Env:ImageName "0000_TestError.ps1" -extendedTimeout
            
            # In Continue mode, the container should complete initialization despite the error
            WaitForLog $Env:ImageName "Initialization completed" -extendedTimeout
        }

        It 'Error is logged but does not stop execution' {
            WaitForLog $Env:ImageName "Forced error due to environment variable SBS_TESTERROR" -extendedTimeout
            WaitForLog $Env:ImageName "SbsRunScriptsInDirectory completed" -extendedTimeout
        }

        It 'Async initialization mode is used' {
            WaitForLog $Env:ImageName "init scripts asynchronously" -extendedTimeout
        }

        It 'Container stays running' {
            $status = docker ps --filter "name=$Env:ImageName" --format "{{.Status}}"
            $status | Should -Match "Up"
        }

        AfterAll {
            docker compose -f servercore2022/compose-erroraction-continue-async.yaml down;
        }
    }
}
