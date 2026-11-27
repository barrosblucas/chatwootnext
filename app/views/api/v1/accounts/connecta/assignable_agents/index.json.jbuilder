json.grouped @grouped
json.conversation_org_unit_id @conversation_org_unit_id
json.groups @groups do |group|
  json.org_unit_id group[:org_unit_id]
  json.org_unit_name group[:org_unit_name]
  json.agents group[:agents] do |agent|
    json.partial! 'api/v1/models/agent', formats: [:json], resource: agent
  end
end
