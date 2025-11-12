# ECE9433-SoC-Design-Project
NYU ECE9433 Fall2025 SoC Design Project
Author:
Zhaoyu Lu
Jiaying Yong
Fengze Yu

### Quick setup

```bash
.setup.sh
```

The script fetches the PicoRV32 core from the official YosysHQ repository, and drops it into `third_party/picorv32/`. Re-run it at any time to update to the currently revision.
(git clone https://github.com/YosysHQ/picorv32.git third_party/picorv32)

Feel free to add additional dependencies by following the same pattern (create a subdirectory under `third_party/`, document the source in this README, and extend `setup.sh` so everyone stays in sync).
