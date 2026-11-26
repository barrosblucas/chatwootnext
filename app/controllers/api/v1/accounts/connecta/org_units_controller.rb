class Api::V1::Accounts::Connecta::OrgUnitsController < Api::V1::Accounts::BaseController
  # Read-only catalog for the dashboard sector filter: only id/name of the
  # enabled units readable under exactly the same account-scoped rule as
  # choosing `connecta_org_unit_id` (DashboardTabs: native account admin or a
  # usable projection with a read-grant prefix). No inbox/team mapping, no
  # write surface, no cross-account data. Missing or unusable projections fail
  # closed to an empty list, never an error that probes grants.
  def index
    units = Connecta::Scope::DashboardTabs.authorized_units(user: current_user, account: Current.account)
    projection = Connecta::Scope::Projection.new(current_user)
    manager = projection.usable? && projection.granted_paths(['gerir']).any?
    render json: { org_units: units.map { |unit| { id: unit.id, name: unit.name } }, connecta_manager: manager }
  end
end
