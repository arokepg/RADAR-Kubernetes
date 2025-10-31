from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC

class LoginPage:
    def __init__(self, wait: WebDriverWait):
        self.wait = wait
        self.SIGN_IN_BUTTON = (By.XPATH, "//a[contains(text(), 'Sign in')]")
        self.LOGIN_BUTTON = (By.XPATH, "//button[contains(text(), 'Login')]")
        self.EMAIL_INPUT = (By.ID, "identifier")
        self.PASSWORD_INPUT = (By.ID, "password")
        self.ERROR_MESSAGE = (By.XPATH, "//span[contains(., 'The provided credentials are invalid')]")
        self.SUCCESS_MESSAGE = (By.XPATH, f"//*[contains(text(), 'You are logged in as ')]")

    def enter_email(self, email):
        email_field = self.wait.until(EC.visibility_of_element_located(self.EMAIL_INPUT))
        email_field.clear()
        email_field.send_keys(email)

    def enter_password(self, password):
        password_field = self.wait.until(EC.visibility_of_element_located(self.PASSWORD_INPUT))
        password_field.clear()
        password_field.send_keys(password)

    def click_sign_in(self):
        self.wait.until(EC.element_to_be_clickable(self.SIGN_IN_BUTTON)).click()

    def click_login(self):
        self.wait.until(EC.element_to_be_clickable(self.LOGIN_BUTTON)).click()

    def get_login_success_message(self):
        success_element = self.wait.until(EC.visibility_of_element_located(self.SUCCESS_MESSAGE))
        return success_element.text

    def get_login_error_message(self):
        error_element = self.wait.until(EC.visibility_of_element_located(self.ERROR_MESSAGE))
        return error_element.text