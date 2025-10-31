from selenium import webdriver
from selenium.webdriver.support.ui import WebDriverWait

from pages.login_page import LoginPage


def _get_wait_timeout(context) -> int:
    try:
        return int(context.config.userdata.get("timeout_s", 20))
    except Exception:
        return 20

def before_all(context):
    context.cache = {
        "management_portal_token": None,
        "armt_source_type_json": None,
        "organization_json": None,
        "project_json": None,
        "armt_project_source_json": None,
        "test_subject_id": None,
        "secrets": None,
        "armt_meta_token": None,
        "armt_refresh_token": None,
        "armt_access_token": None,
        "rest_auth_registration_json": None,
        "fitbit_user_json": None,
    }
    context.state = {
        "database": {},
        "storage": {},
    }

def before_scenario(context, scenario):
    """
    Set up the WebDriver before EACH scenario tagged with @needs_browser.
    """
    if "needs_browser" in scenario.effective_tags:
        options = webdriver.ChromeOptions()
        options.add_argument("--disable-gpu")
        options.add_argument("--disable-dev-shm-usage")
        options.add_argument("--window-size=1280,1024")
        # To add for running in CI/headless environments
        # options.add_argument("--headless")

        context.browser = webdriver.Chrome(options=options)
        context.ui_wait = WebDriverWait(context.browser, _get_wait_timeout(context))
        context.login_page = LoginPage(context.ui_wait)

def after_scenario(context, scenario):
    """
    Tear down the WebDriver after EACH scenario tagged with @needs_browser.
    """
    if "needs_browser" in scenario.effective_tags:
        browser = getattr(context, "browser", None)
        if browser:
            try:
                browser.quit()
            except Exception:
                pass
            context.browser = None
