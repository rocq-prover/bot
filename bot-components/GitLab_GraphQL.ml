module GetRetriedJobs =
  [%graphql
  {|
  query getRetriedJobs($fullPath: ID!, $jobId: JobID!) {
    project(fullPath: $fullPath) {
      job(id: $jobId) {
        pipeline {
          ... on Pipeline {
            jobs(retried: true, first: 100) {
              count
              nodes {
                name
              }
            }
          }
        }
      }
    }
  }
|}]

module SearchProjects =
  [%graphql
  {|
query searchProjects($search: String!) {
  projects(search: $search, first: 10) {
    nodes {
      id
      fullPath
      namespace {
        fullPath
      }
      path
    }
  }
}
|}]

module GetCIConfigFile =
  [%graphql
  {|
query getCIConfig($fullPath: ID!) {
  project(fullPath: $fullPath) {
    repository {
      blobs(paths: [".gitlab-ci.yml", ".gitlab-ci.yaml"]) {
        nodes {
          rawBlob
          path
        }
      }
    }
  }
}
|}]
