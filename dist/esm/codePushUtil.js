/**
 * Callback / error / logging utilities.
 */
export class CodePushUtil {
    /**
     * Performs a copy of all members of fromParameter to toParameter, with the condition that they are unassigned or null in toParameter.
     */
    static copyUnassignedMembers(fromParameter, toParameter) {
        for (let key in fromParameter) {
            if (toParameter[key] === undefined || toParameter[key] === null) {
                toParameter[key] = fromParameter[key];
            }
        }
    }
    /**
     * Given two Cordova style callbacks for success and error, this function returns a node.js
     * style callback where the error is the first parameter and the result the second.
     */
    static getNodeStyleCallbackFor(successCallback, errorCallback) {
        return (error, result) => {
            if (error) {
                errorCallback && errorCallback(error);
            }
            else {
                successCallback && successCallback(result);
            }
        };
    }
    /**
     * Gets the message of an error, if any. Otherwise it returns the empty string.
     */
    static getErrorMessage(e) {
        return e && e.message || e && e.toString() || "";
    }
    /**
     * Logs a message using the CodePush tag.
     */
    static logMessage(msg) {
        console.log(CodePushUtil.TAG + " " + msg);
    }
    /**
     * Logs an error message using the CodePush tag.
     */
    static logError(message, error) {
        const errorMessage = `${message || ""} ${CodePushUtil.getErrorMessage(error)}`;
        const stackTrace = error && error.stack ? `. StackTrace: ${error.stack}` : "";
        console.error(`${CodePushUtil.TAG} ${errorMessage}${stackTrace}`);
    }
}
/**
 * Tag used for logging to the console.
 */
CodePushUtil.TAG = "[CodePush]";
/**
 * Logs the error to the console and then forwards it to the provided ErrorCallback, if any.
 */
CodePushUtil.invokeErrorCallback = (error, errorCallback) => {
    if (errorCallback) {
        return errorCallback(error);
    }
    CodePushUtil.logError(null, error);
};
/**
 * Logs the error to the console and then throws the error.
 */
CodePushUtil.throwError = (error) => {
    CodePushUtil.logError(null, error);
    throw error;
};
//# sourceMappingURL=codePushUtil.js.map