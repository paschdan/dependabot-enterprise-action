#!/usr/bin/env bash
# copyright 2020  paschdan
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -o errexit
set -o pipefail

if [[ "$INPUT_DEBUG" == "on" ]]; then
  env
  set -x
fi

export GITHUB_ENTERPRISE_HOSTNAME=$(cut -d '/' -f 3 <<<"$GITHUB_SERVER_URL")
export PROJECT_PATH=$GITHUB_REPOSITORY

export GITHUB_ENTERPRISE_ACCESS_TOKEN=$INPUT_TOKEN
export GITHUB_ACCESS_TOKEN=$INPUT_GITHUB_TOKEN
export PACKAGE_MANAGER=$INPUT_PACKAGE_MANAGER

export UPDATE_PR=$INPUT_UPDATE_PR

if [[ -z "$UPDATE_PR" ]]; then
  bundle exec ruby ./create_or_update_prs.rb
else
  bundle exec ruby ./update_single_pr.rb
fi
