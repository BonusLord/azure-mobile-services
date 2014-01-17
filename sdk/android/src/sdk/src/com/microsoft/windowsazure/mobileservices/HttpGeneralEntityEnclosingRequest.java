package com.microsoft.windowsazure.mobileservices;

import java.net.URI;

import org.apache.http.client.methods.HttpEntityEnclosingRequestBase;

/**
 * HttpRequest that allows an entity to be set on any type of HTTP request.  Prevents
 * ClassCastExceptions when trying to invoke an API with a request body using certain
 * HTTP methods. 
 */
public class HttpGeneralEntityEnclosingRequest extends HttpEntityEnclosingRequestBase {

	private final String methodName;

	public HttpGeneralEntityEnclosingRequest(String methodName) {
		this.methodName = methodName;
	}
	
	public HttpGeneralEntityEnclosingRequest(String methodName, URI uri) {
		this.methodName = methodName;
		setURI(uri);
	}
	
	public HttpGeneralEntityEnclosingRequest(String methodName, String uri) {
		this.methodName = methodName;
		setURI(URI.create(uri));
	}
	
	@Override
	public String getMethod() {
		return methodName;
	}
}
