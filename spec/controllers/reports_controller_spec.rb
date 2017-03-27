require 'rails_helper'

describe ReportsController, vcr: true do
  render_views

  describe '#show' do
    context 'without an active scenario' do
      it 'redirects when no scenario has been started' do
        get :show, params: { id: 'sample' }

        expect(response).to be_redirect
      end
    end

    context 'with an active scenario' do
      before { session[:setting] = Setting.new(api_session_id: 648_695) }
      before { FactoryGirl.create(:tab, key: 'demand') }

      it 'renders the report' do
        get :show, params: { id: 'sample' }

        expect(response).to be_success
        expect(response).to render_template(:show)
      end

      it 'renders 404 when the specified report does not exist' do
        expect { get :show, params: { id: 'four-oh-four' } }
          .to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end
end