// Minimal wait program - waits indefinitely until terminated
// Compiles to ~10KB, uses <1MB memory
#include <windows.h>
#include <stdio.h>

int main() {
    printf("wait.exe: Waiting indefinitely...\n");
    fflush(stdout);
    
    // Create a manual-reset event that will never be signaled
    HANDLE hEvent = CreateEvent(NULL, TRUE, FALSE, NULL);
    if (hEvent) {
        // Wait forever (INFINITE = 0xFFFFFFFF)
        WaitForSingleObject(hEvent, INFINITE);
        CloseHandle(hEvent);
    }
    
    printf("wait.exe: Received termination signal, exiting.\n");
    fflush(stdout);
    return 0;
}
