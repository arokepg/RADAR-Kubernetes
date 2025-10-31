from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC

class LoginPage:
    def __init__(self, browser, wait: WebDriverWait):
        self.browser = browser
        self.wait = wait

    def enter_email(self, email):
        self.browser.find_element(By.ID, "identifier").send_keys(email)

    def enter_password(self, password):
        self.browser.find_element(By.ID, 'password').send_keys(password)

    def click_sign_in(self):
        self.browser.find_element(By.XPATH, "//a[contains(text(), 'Sign in')]").click()

    def click_login(self):
        self.browser.find_element(By.XPATH, "//button[contains(text(), 'Login')]").click()

    def get_info_message(self, message):
        info_locator = (By.XPATH, f"//*[contains(text(), '{message}')]")
        try:
            self.wait.until(EC.visibility_of_element_located(info_locator))
        except Exception as e:
            raise AssertionError(
                f"Timed out waiting for info message containing: '{message}'. Error: {e}"
            )

    def get_login_error_message(self):
        error_locator = (By.XPATH, "//span[contains(., 'The provided credentials are invalid')]")
        try:
            self.wait.until(EC.visibility_of_element_located(error_locator))
        except Exception:
            raise AssertionError("Could not find the credentials error message element.")
