// Copyright 2024 Nick-Ilhan Atamgüc
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

/// Checks if a `data` exists in `self`.
///
/// Computes in **O(n²)** time.
pub fn contains(self: []const u8, data: []const u8) bool {
    outer: for (0..self.len) |xidx| {
        if (self.len < (xidx + data.len)) {
            break :outer;
        }

        for (data, 0..) |byte, yidx| {
            if (self[xidx + yidx] != byte) {
                continue :outer;
            }
        }

        return true;
    }
    return false;
}
