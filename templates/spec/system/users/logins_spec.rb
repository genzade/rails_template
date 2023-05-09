# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Users::Logins", type: :system do
  it "with valid email and password" do
    create(:user, username: "user123", email: "user@example.com", password: "Password1!asdf")
    sign_in_with "user@example.com", "Password1!asdf"

    expect(page).to have_current_path(root_path)
  end

  it "tries with invalid password" do
    create(:user, username: "user123", email: "user@example.com", password: "Password1!asdf")
    sign_in_with "user@example.com", "wrong_password"

    expect_page_to_display_sign_in_error

    expect(page).to have_current_path(new_user_session_path)
  end

  it "tries with invalid email" do
    sign_in_with "unknown.email@example.com", "password"

    expect_page_to_display_sign_in_error

    expect(page).to have_current_path(new_user_session_path)
  end

  def sign_in_with(email, password)
    visit new_user_session_path
    fill_in "user_email", with: email
    fill_in "user_password", with: password
    click_button "Log in"
  end

  def expect_page_to_display_sign_in_error
    expect(page).to have_content(
      I18n.t("devise.failure.invalid", authentication_keys: "Email")
    )
  end
end
