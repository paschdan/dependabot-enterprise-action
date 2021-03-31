# This script is designed to loop through all dependencies in a GHE, GitLab or
# Azure DevOps project, creating PRs where necessary.

require "json"
require "dependabot/file_fetchers"
require "dependabot/file_parsers"
require "dependabot/update_checkers"
require "dependabot/file_updaters"
require "dependabot/pull_request_creator"
require "dependabot/pull_request_updater"
require "dependabot/omnibus"

credentials = [
  {
    "type" => "git_source",
    "host" => "github.com",
    "username" => "x-access-token",
    "password" => ENV["GITHUB_ACCESS_TOKEN"] # A GitHub access token with read access to public repos
  }
]

# Full name of the repo you want to create pull requests for.
repo_name = ENV["PROJECT_PATH"] # namespace/project

# Directory where the base dependency files are.
directory = ENV["DIRECTORY_PATH"] || "/"

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

if ENV["GITHUB_ENTERPRISE_ACCESS_TOKEN"]
  credentials << {
    "type" => "git_source",
    "host" => ENV["GITHUB_ENTERPRISE_HOSTNAME"], # E.g., "ghe.mydomain.com",
    "username" => "x-access-token",
    "password" => ENV["GITHUB_ENTERPRISE_ACCESS_TOKEN"] # A GHE access token with API permission
  }

  source = Dependabot::Source.new(
    provider: "github",
    hostname: ENV["GITHUB_ENTERPRISE_HOSTNAME"],
    api_endpoint: "https://#{ENV['GITHUB_ENTERPRISE_HOSTNAME']}/api/v3/",
    repo: repo_name,
    directory: directory,
    branch: nil,
  )
else
  source = Dependabot::Source.new(
    provider: "github",
    repo: repo_name,
    directory: directory,
    branch: nil,
  )
end

##############################
# Fetch the dependency files #
##############################
puts "Fetching #{package_manager} dependency files for #{repo_name}"
fetcher = Dependabot::FileFetchers.for_package_manager(package_manager).new(
  source: source,
  credentials: credentials,
)

files = fetcher.files
commit = fetcher.commit

github_client = Dependabot::Clients::GithubWithRetries.for_source(
  source: source,
  credentials: credentials
)
# list all the open PR's
github_client.pull_requests(repo_name, state: 'open')

# store the gh pr requests for all pages
repo_pull_requests = []

# deal with busted paging in octokit
# https://github.com/octokit/octokit.rb/issues/732#issuecomment-237794222
puts "Requesting all pull requests from #{repo_name}"
last_response = github_client.last_response
while true
  next_page_gh_pull_requests = last_response.data
  next_page_gh_pull_requests.each do |pr|

    # Add other checks here
    # like it failed the test suite?
    # https://developer.github.com/v3/checks/suites/#list-check-suites-for-a-specific-ref

    # only take the dependabot PRs that aren't up to date
 #
    is_dependabot_pr = pr.head.label.include?("dependabot")

    if is_dependabot_pr
      repo_pull_requests << pr
    end
  end

  # manual page handling - load the next page of data and loop
  next_page = last_response.rels[:next]
  break unless next_page
  last_response = next_page.get
end

##############################
# Parse the dependency files #
##############################
puts "Parsing dependencies information"
parser = Dependabot::FileParsers.for_package_manager(package_manager).new(
  dependency_files: files,
  source: source,
  credentials: credentials,
)

dependencies = parser.parse

found_prs = []

dependencies.select(&:top_level?).each do |dep|
  #########################################
  # Get update details for the dependency #
  #########################################
  checker = Dependabot::UpdateCheckers.for_package_manager(package_manager).new(
    dependency: dep,
    dependency_files: files,
    credentials: credentials,
  )

  next if checker.up_to_date?

  requirements_to_unlock =
    if !checker.requirements_unlocked_or_can_be?
      if checker.can_update?(requirements_to_unlock: :none) then :none
      else :update_not_possible
      end
    elsif checker.can_update?(requirements_to_unlock: :own) then :own
    elsif checker.can_update?(requirements_to_unlock: :all) then :all
    else :update_not_possible
    end

  next if requirements_to_unlock == :update_not_possible

  updated_deps = checker.updated_dependencies(
    requirements_to_unlock: requirements_to_unlock
  )

  #####################################
  # Generate updated dependency files #
  #####################################
  print "  - Updating #{dep.name} from #{dep.version} to #{checker.latest_version}"
  updater = Dependabot::FileUpdaters.for_package_manager(package_manager).new(
    dependencies: updated_deps,
    dependency_files: files,
    credentials: credentials,
  )

  updated_files = updater.updated_dependency_files
  ## TODO: update pr if already existing

  found_pr = false

  repo_pull_requests.each_with_index  do |pr, i|

    next if !pr.title.include?("ump #{dep.name} from")

    found_pr = true

    upstream_pr = github_client.pull_request(repo_name, pr.number)
    pr_is_uptodate = pr.title.include?("to #{checker.latest_version}")
    # skip if pr is already mergable
    if upstream_pr.mergeable && pr_is_uptodate
      puts " skipped"
      found_prs << i
      next
    end

    pr_updater = Dependabot::PullRequestUpdater.new(
        source: source,
        base_commit: commit,
        old_commit: pr.base.sha,
        files: updated_files,
        credentials: credentials,
        pull_request_number: pr.number,
        author_details: { email: "dependabot@users.noreply.#{ENV["GITHUB_ENTERPRISE_HOSTNAME"]}", name: "dependabot" }
      )
    pr_updater.update
    puts " updated PR #{pr.number}"
    found_prs << i
  end
  next if found_pr

  ########################################
  # Create a pull request for the update #
  ########################################
  pr_creator = Dependabot::PullRequestCreator.new(
    source: source,
    base_commit: commit,
    dependencies: updated_deps,
    files: updated_files,
    credentials: credentials,
    assignees: [(ENV["PULL_REQUESTS_ASSIGNEE"])&.to_i],
    label_language: true,
    author_details: { email: "dependabot@users.noreply.#{ENV["GITHUB_ENTERPRISE_HOSTNAME"]}", name: "dependabot" }
  )
  pull_request = pr_creator.create
  puts " submitted"

  next unless pull_request
end

found_prs.each do |repo_pull_requests_index|
  repo_pull_requests.delete_at(repo_pull_requests_index)
end

puts "Left PRs: #{repo_pull_requests.length()}"
puts "cleaning up left over prs"
repo_pull_requests.each do |pr|
  github_client.close_pull_request(repo_name, pr.number)
end

puts "Done"
