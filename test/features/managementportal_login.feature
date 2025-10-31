@needs_browser
Feature: Management Portal login flow

  Scenario Outline: User signs in to Management Portal
    Given I open the Management Portal homepage
    When I click sign in button
    Then I should be redirected to the login page
    When I enter <email> and <password>
    And I confirm the sign in on the login page
    Then I should see <message>
    Examples: Credentials
      | email             | password         | message                               |
      | admin@example.com | secret           | Logged in as admin                    |
      | invalid_user      | invalid_password | The provided credentials are invalid. |
