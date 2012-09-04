require 'spec_helper'

describe "Loading a preset scenario", :js => true do
  it "should create a new scenario from a preset" do
    visit home_path
    click_link "Start an existing scenario"
    # scenario_id = 1
    click_link "Referentiescenario 2030 gebaseerd op ..."

    page.should have_content('Household energy demand')

    settings = page.evaluate_script('App.settings.toJSON()')

    settings['area_code'].should == 'nl'
    settings['end_year'].should == 2030
    settings['scenario_id'].should == 1

    new_scenario_id = settings['api_session_id']
    remote_scenario = Api::Scenario.find new_scenario_id

    remote_scenario.scenario_id.should == 1
    remote_scenario.end_year.should == 2030
    remote_scenario.area_code.should == 'nl'

  end
end