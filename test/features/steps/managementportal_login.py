from behave import given, when, then, fixture, use_fixture
from pages.login_page import LoginPage
from urllib.parse import urlparse
from base import get_logger, get_credential_value, get_secret
from selenium.common.exceptions import TimeoutException


logger = get_logger()

@given('I open the Management Portal homepage')
def step_given_on_login_page(context):
    base_url = context.config.userdata.get("url")
    if not base_url:
        raise ValueError("'url' not set in userdata")
    context.browser.get(f'{base_url}/managementportal')
    logger.info("Navigated to Management Portal homepage")

@when('I click sign in button')
def step_when_click_sign_in_button(context):
    context.login_page.click_sign_in()
    logger.info("Clicked on sign in button")

@then('I should be redirected to the login page')
def step_then_redirect_to_login_page(context):
    def url_has_kratos_login_challenge(_):
        try:
            url = urlparse(context.browser.current_url)
            path_correct = url.path.startswith("/kratos-ui/auth/oauth-login")
            query_correct = "login_challenge" in (url.query or "")
            return path_correct and query_correct
        except Exception:
            return False

    try:
        context.ui_wait.until(url_has_kratos_login_challenge)
        logger.info("Redirected to login page")
    except TimeoutException:
        raise AssertionError(
            f"Expected to be on Kratos login challenge page, but was on {context.browser.current_url}")

@when('I enter {email} and {password}')
def step_when_enter_credentials(context, email, password):
    try:
        final_email = get_credential_value(context, email)
        final_password = get_secret('management_portal', 'managementportal', 'common_admin_password', context=context) \
            if password.startswith("$") \
            else password
    except ValueError as e:
        logger.error(str(e))
        raise

    context.login_page.enter_email(final_email)
    context.login_page.enter_password(final_password)
    logger.info(f"Entered credentials (email: {email})")

@when('I confirm the sign in on the login page')
def step_when_click_login_button(context):
    context.login_page.click_login()
    logger.info("Clicked on login button")

@then('I should see {message}')
def step_then_see_message(context, message):
    actual_message = ""
    try:
        if "invalid" in message.lower():
            # This method should wait for the error and return its text
            actual_message = context.login_page.get_login_error_message()
        else:
            # This method should wait for the success message and return its text
            actual_message = context.login_page.get_login_success_message()

        assert message.lower() in actual_message.lower()
        logger.info(f"Successfully found expected message: {message}")

    except TimeoutException:
        logger.error(f"Timed out waiting for message element (expected: '{message}')")
        raise
    except AssertionError:
        logger.error(f"Message mismatch. Expected: '{message}' to be part of displayed message: '{actual_message}'")
        raise
