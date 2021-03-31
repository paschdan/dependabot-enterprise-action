# This script is designed to be copied into an interactive Ruby session, to
# give you an idea of how the different classes in Dependabot Core fit together.
#
# It's used regularly by the Dependabot team to manually debug issues, so should
# always be up-to-date.
require "json"
require "dependabot/file_fetchers"
require "dependabot/file_parsers"
require "dependabot/update_checkers"
require "dependabot/file_updaters"
require "dependabot/pull_request_updater"
require "dependabot/omnibus"

# GitHub credentials with write permission to the repo you want to update
# (so that you can create a new branch, commit and pull request).
# If using a private registry it's also possible to add details of that here.
 #

credentials = [
{
  "type" => "git_source",
  "host" => ENV["GITHUB_ENTERPRISE_HOSTNAME"], # E.g., "ghe.mydomain.com",
  "username" => "x-access-token",
  "password" => ENV["GITHUB_ENTERPRISE_ACCESS_TOKEN"] # A GHE access token with API permission
}
]

credentials << {
  "type" => "git_source",
  "host" => ENV["GITHUB_ENTERPRISE_HOSTNAME"], # E.g., "ghe.mydomain.com",
  "username" => "x-access-token",
  "password" => ENV["GITHUB_ENTERPRISE_ACCESS_TOKEN"] # A GHE access token with API permission
}


# Full name of the repo you want to create pull requests for.
repo_name = ENV["PROJECT_PATH"] # namespace/project

# Directory where the base dependency files are.
directory = ENV["DIRECTORY_PATH"] || "/"

# update strategt
update_strategy = ENV["UPDATE_STRATEGY"] || ""


# Name of the package manager you'd like to do the update for. Options are:
# - bundler
# - pip (includes pipenv)
# - npm_and_yarn
# - maven
# - gradle
# - cargo
# - hex
# - composer
# - nuget
# - dep
# - go_modules
# - elm
# - submodules
# - docker
# - terraform
package_manager = ENV["PACKAGE_MANAGER"] || "bundler"

# Name of the dependency you'd like to update. (Alternatively, you could easily
# modify this script to loop through all the dependencies returned by
# `parser.parse`.)
update_pr = ENV["UPDATE_PR"]

source = Dependabot::Source.new(
  provider: "github",
  hostname: ENV["GITHUB_ENTERPRISE_HOSTNAME"],
  api_endpoint: "https://#{ENV['GITHUB_ENTERPRISE_HOSTNAME']}/api/v3/",
  repo: repo_name,
  directory: directory,
  branch: nil,
)
##############################
# Fetch the dependency files #
##############################
fetcher = Dependabot::FileFetchers.for_package_manager(package_manager).
          new(source: source, credentials: credentials)

files = fetcher.files
commit = fetcher.commit

##############################
# Retrieve current commit
##############################

# get our hands on raw github client
github_client = Dependabot::Clients::GithubWithRetries.for_source(
  source: source,
  credentials: credentials
)
current_pr = github_client.pull_request(repo_name, update_pr)

PR_TITLE_GEM_NAME_REGEX = /Bump\s(.+)\sfrom/i.freeze
if title_gem_name = current_pr.title.match(PR_TITLE_GEM_NAME_REGEX)
    pr_gem_name = title_gem_name[1]
  else
    raise StandardError.new(
      "Can't find the gem name from the PR title - #{current_pr.title}" \
      "must be a non-gem update PR, this shouldn't happen!"
    )
  end

# Parse the dependency files #
##############################
parser = Dependabot::FileParsers.for_package_manager(package_manager).new(
  dependency_files: files,
  source: source,
  credentials: credentials,
)

dependencies = parser.parse
dep = dependencies.find { |d| d.name == pr_gem_name }

#########################################
# Get update details for the dependency #
#########################################
checker = Dependabot::UpdateCheckers.for_package_manager(package_manager).new(
  dependency: dep,
  dependency_files: files,
  credentials: credentials,
)

checker.up_to_date?
checker.can_update?(requirements_to_unlock: :own)
updated_deps = checker.updated_dependencies(requirements_to_unlock: :own)

#####################################
# Generate updated dependency files #
#####################################
updater = Dependabot::FileUpdaters.for_package_manager(package_manager).new(
  dependencies: updated_deps,
  dependency_files: files,
  credentials: credentials,
)

updated_files = updater.updated_dependency_files

### OLD
 #
pr_updater = Dependabot::PullRequestUpdater.new(
      source: source,
      base_commit: commit,
      old_commit: current_pr.base.sha,
      files: updated_files,
      credentials: credentials,
      pull_request_number: current_pr.number
    )

pr_update_response = pr_updater.update
puts pr_update_response
puts commit
puts current_pr.head.sha
puts current_pr.base.sha
puts "Updated PR #{current_pr.html_url}"
#### OLD
########################################
# Update PR #
########################################
#pr_creator = Dependabot::PullRequestCreator.new(
#  source: source,
#  base_commit: commit,
#  dependencies: updated_deps,
#  files: updated_files,
#  credentials: credentials,
#)
#pr_creator.create
