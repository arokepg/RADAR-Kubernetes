from behave import given, when, then, fixture, use_fixture
from pages.login_page import LoginPage
from urllib.parse import urlparse
from base import get_logger
from base import retry
from selenium.common.exceptions import TimeoutException


logger = get_logger()

@given('I open the Management Portal homepage')
def step_given_on_login_page(context):
    context.browser.get(f'{context.config.userdata["url"]}/managementportal')
    logger.info("Navigated to login page")

@when('I click sign in button')
def step_when_click_sign_in_button(context):
    retry(lambda: context.login_page.click_sign_in())
    logger.info("Clicked on sign in button")

@then('I should be redirected to the login page')
def step_then_redirect_to_login_page(context):
    def url_has_kratos_login_challenge(_):
        try:
            url = urlparse(context.browser.current_url)
            return url.path.startswith("/kratos-ui/auth/oauth-login") and "login_challenge" in (url.query or "")
        except Exception:
            return False
    try:
        context.ui_wait.until(url_has_kratos_login_challenge)
    except TimeoutException:
        raise AssertionError(
            f"Expected to be on Kratos OAuth login challenge page, but current URL is {context.browser.current_url}")

@when('I enter {email} and {password}')
def step_when_enter_credentials(context, email, password):
    retry(lambda: context.login_page.enter_email(email))
    retry(lambda: context.login_page.enter_password(password))
    logger.info(f"Entered email: {email} and password: {password}")

@when('I confirm the sign in on the login page')
def step_when_click_login_button(context):
    retry(lambda: context.login_page.click_login())
    logger.info("Clicked on login button")

@then('I should see {message}')
def step_then_see_message(context, message):
    try:
        if "invalid" in message.lower():
            context.login_page.get_login_error_message()
        else:
            context.login_page.get_info_message("You are logged in as user")
    except AssertionError as e:
        logger.error(f"Failed to find message: {e}")
        raise
    logger.info(f"Expected message: {message} displayed")
