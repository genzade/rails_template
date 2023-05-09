# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Users::Registrations", type: :system do
  it "by navigating to the page from login page" do
    visit new_user_session_path

    # click_link I18n.t("devise.sessions.new.sign_up")
    click_link "Sign up", match: :first

    expect(page).to have_current_path(new_user_registration_path)
  end

  context "with no details filled in" do
    it "errors with messages, but once filled in, it allows signing up", :aggregate_failures do
      visit new_user_registration_path
      click_button "Sign up"

      expect(page).to have_content "Email can't be blank"
      expect(page).to have_content "Password can't be blank"

      sign_up_with email: "valid@example.com", password: "Password"

      expect(page).to have_current_path(root_path)
    end
  end

  context "when passwords don't match" do
    it "renders an error" do
      visit new_user_registration_path
      sign_up_with(email: "valid@example.com", password: "Password1!asdf", same_password: false)

      expect(page).to have_text("Password confirmation doesn't match Password")
    end
  end

  def sign_up_with(**args)
    password = args.fetch(:password)

    fill_in "user_username", with: "my_username"
    fill_in "user_email", with: args.fetch(:email)
    fill_in "user_password", with: password

    password_confirmation = args.fetch(:same_password, true) ? password : "-#{password}-"
    fill_in "user_password_confirmation", with: password_confirmation

    click_button "Sign up"
  end
end
